{ config, lib, pkgs, ... }:
# `kexec-reboot`: reboot into the newest system generation without the
# firmware's POST and without unlocking the LUKS key device in the initrd by
# hand.
#
# The passphrase is asked for while the system is still up and checked
# against the device. It then travels in RAM only: as one file in a small
# extra cpio appended to the next initrd. systemd-cryptsetup picks it up on
# its own from /etc/cryptsetup-keys.d/<name>.key (crypttab has no key file
# for the device), and the initrd deletes it straight after the unlock.
# init_on_free=1 zeroes freed memory, so deleted copies don't linger.
#
# Nothing is written to disk. If the kexec'd boot fails, a normal reboot
# prompts for the passphrase as usual.
let
  cfg = config.homelab.kexecUnlock;
  luks = config.boot.initrd.luks.devices.${cfg.device};
  keyPath = "etc/cryptsetup-keys.d/${cfg.device}.key";

  kexecReboot = pkgs.writeShellApplication {
    name = "kexec-reboot";
    runtimeInputs = with pkgs; [ coreutils cpio cryptsetup kexec-tools systemd ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "kexec-reboot: run as root" >&2
        exit 1
      fi
      toplevel=$(readlink -f "''${1:-/nix/var/nix/profiles/system}")
      for f in kernel initrd init kernel-params; do
        [ -e "$toplevel/$f" ] || { echo "kexec-reboot: $toplevel has no $f" >&2; exit 1; }
      done
      echo "Will reboot into $toplevel"

      umask 077
      work=$(mktemp -d /run/kexec-reboot.XXXXXX) # /run is RAM
      cleanup() {
        rm -f -- "$work/root/${keyPath}" "$work/key.cpio" "$work/initrd"
        rmdir -- "$work/root/etc/cryptsetup-keys.d" "$work/root/etc" "$work/root" "$work" 2>/dev/null || true
      }
      trap cleanup EXIT

      # read fails at end of input without a newline even when it read text.
      passphrase=""
      IFS= read -rsp "Passphrase for ${cfg.device}: " passphrase || [ -n "$passphrase" ]
      echo
      if ! printf '%s' "$passphrase" |
        cryptsetup open --test-passphrase --key-file=- ${lib.escapeShellArg luks.device}; then
        echo "kexec-reboot: wrong passphrase, not rebooting" >&2
        exit 1
      fi

      # The kernel unpacks this before the main archive and doesn't create
      # parent directories, so etc/ is in it too, with the mode it has in the
      # main archive.
      mkdir -p "$work/root/etc/cryptsetup-keys.d"
      chmod 0755 "$work/root/etc"
      chmod 0700 "$work/root/etc/cryptsetup-keys.d"
      printf '%s' "$passphrase" > "$work/root/${keyPath}"
      unset passphrase
      (cd "$work/root" &&
        printf '%s\n' etc etc/cryptsetup-keys.d ${keyPath} |
        cpio --quiet -o -H newc -R 0:0) > "$work/key.cpio"
      rm -f -- "$work/root/${keyPath}"

      # Splice the key archive in after the uncompressed cpio archives at the
      # start of the initrd (CPU microcode) and before the compressed main
      # one. The kernel doesn't reliably read an archive appended after a
      # compressed one, and early microcode must stay first.
      initrd=$toplevel/initrd
      total=$(stat -c %s "$initrd")
      offset=0
      bytes() { tail -c +$((offset + 1)) "$initrd" | head -c "$1"; }
      while [ $((offset + 110)) -le "$total" ]; do
        if [ "$(bytes 6 | tr -d '\0')" = 070701 ]; then
          # newc header: filesize at 54, namesize at 94, both 8 hex digits;
          # name and data are each padded to 4 bytes.
          header=$(bytes 110)
          filesize=$((16#''${header:54:8}))
          namesize=$((16#''${header:94:8}))
          offset=$((offset + ((110 + namesize + 3) & ~3) + ((filesize + 3) & ~3)))
        elif [ "$(bytes 4 | od -An -tx1 | tr -d ' \n')" = 00000000 ]; then
          offset=$((offset + 4)) # zero padding between archives
        else
          break
        fi
      done
      {
        head -c "$offset" "$initrd"
        cat "$work/key.cpio"
        tail -c +$((offset + 1)) "$initrd"
      } > "$work/initrd"
      rm -f -- "$work/key.cpio"

      kexec --load "$toplevel/kernel" --initrd="$work/initrd" \
        --command-line="init=$toplevel/init $(cat "$toplevel/kernel-params")"
      cleanup
      trap - EXIT

      systemctl kexec
    '';
  };
in {
  options.homelab.kexecUnlock = {
    enable = lib.mkEnableOption "kexec-reboot, which carries the LUKS passphrase into the next initrd";
    device = lib.mkOption {
      type = lib.types.str;
      default = "cryptkey";
      description = "boot.initrd.luks.devices entry unlocked by passphrase.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.luks.devices ? ${cfg.device} && luks.keyFile == null;
        message = "homelab.kexecUnlock.device must be a LUKS device unlocked by passphrase.";
      }
    ];

    environment.systemPackages = [ kexecReboot ];

    # Zero pages when they are freed, so the copies of the passphrase that
    # kexec-reboot and the initrd delete don't linger in RAM.
    boot.kernelParams = [ "init_on_free=1" ];

    # Delete the carried passphrase as soon as the device is open. Without
    # kexec-reboot there is no such file and this does nothing.
    boot.initrd.systemd.storePaths = [ "${pkgs.coreutils}/bin/rm" ];
    boot.initrd.systemd.services.forget-kexec-passphrase = {
      description = "Delete the passphrase kexec-reboot carried in";
      after = [ "systemd-cryptsetup@${cfg.device}.service" ];
      before = [ "cryptsetup.target" ];
      wantedBy = [ "cryptsetup.target" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/rm -f /${keyPath}";
      };
    };
  };
}
