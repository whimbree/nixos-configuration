# Deterministic per-MicroVM age keys, derived on the host from one shared seed.
#
# For every VM flagged `sops = true` in vm-registry.nix a derive-vm-key-<vm>.service
# builds /persist/etc/sops/vm-keys/<vm>.img, holding the HKDF-derived age identity,
# just before microvm@<vm>.service starts. Because derivation is deterministic, a
# lost/deleted image rebuilds to the same identity (self-heal); only the single
# seed (secrets/microvm-key-seed.yaml) needs backing up.
#
# The seed is NOT kept decrypted on disk. Each derive unit decrypts it on demand,
# in memory, using bastion's ssh host key (converted to an age identity with
# ssh-to-age) -- so no standing /run/secrets/microvm-key-seed plaintext exists. The
# plaintext only lives in the unit's process for the moment it builds the image.
#
# See docs/sops-microvm-key-image.md.
{ lib, pkgs, ... }:
let
  vmLib = import ../lib/vm-lib.nix { inherit lib; };
  sopsVMs = lib.filterAttrs (_n: v: v.sops or false) vmLib.getAllVMs;

  seedFile = ../../secrets/microvm-key-seed.yaml;
  sshHostKey = "/etc/ssh/ssh_host_ed25519_key";

  # Wraps the shared derivation helper. Reads the base64 seed on stdin, prints
  # the age identity (or --pub for the recipient).
  deriveAgeKey = pkgs.writeShellApplication {
    name = "derive-age-key";
    runtimeInputs = [ pkgs.python3 pkgs.age ];
    text = ''exec python3 ${../lib/derive-age-key.py} "$@"'';
  };

  # Decrypt the seed on demand using bastion's ssh host key (no standing plaintext).
  # Prints the base64 seed on stdout; callers pipe it into derive-age-key.
  decryptSeed = pkgs.writeShellApplication {
    name = "decrypt-microvm-key-seed";
    runtimeInputs = [ pkgs.ssh-to-age pkgs.sops ];
    text = ''
      SOPS_AGE_KEY="$(ssh-to-age -private-key -i ${sshHostKey})" \
        sops -d --extract '["microvm-key-seed"]' ${seedFile}
    '';
  };

  # Convenience for authoring on bastion: derive a VM's pubkey straight from the
  # on-demand-decrypted seed. On a workstation, use scripts/sops-vm-pubkey instead
  # (decrypts via your admin key).
  sopsVmPubkey = pkgs.writeShellApplication {
    name = "sops-vm-pubkey";
    runtimeInputs = [ deriveAgeKey decryptSeed ];
    text = ''
      vm="''${1:?usage: sops-vm-pubkey <vm>}"
      decrypt-microvm-key-seed | derive-age-key --pub "$vm"
    '';
  };
in {
  environment.systemPackages = [ deriveAgeKey decryptSeed sopsVmPubkey ];

  systemd.services = lib.mapAttrs' (vmName: _vm:
    lib.nameValuePair "derive-vm-key-${vmName}" {
      description = "Derive + build sops age key image for MicroVM ${vmName}";
      before = [ "microvm@${vmName}.service" ];
      requiredBy = [ "microvm@${vmName}.service" ];
      unitConfig.RequiresMountsFor = "/persist";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ deriveAgeKey decryptSeed pkgs.e2fsprogs pkgs.coreutils ];
      script = ''
        set -euo pipefail
        img=/persist/etc/sops/vm-keys/${vmName}.img
        dir=$(dirname "$img")
        install -d -m 0750 -o root -g kvm "$dir"

        # Decrypt the seed in memory and derive this VM's key. The plaintext seed
        # never touches disk.
        want=$(decrypt-microvm-key-seed | derive-age-key ${vmName})

        # If the image already holds the derived key, do nothing. Read the file
        # straight out of the ext4 image without mounting it.
        if [ -f "$img" ]; then
          have=$(debugfs -R "cat key.txt" "$img" 2>/dev/null | tr -d '\0\n' || true)
          if [ "$have" = "$want" ]; then
            echo "key image for ${vmName} up to date"
            exit 0
          fi
          echo "key image for ${vmName} stale or unreadable, rebuilding"
        fi

        stage=$(mktemp -d)
        trap 'rm -rf "$stage"' EXIT
        printf '%s\n' "$want" > "$stage/key.txt"
        chmod 0400 "$stage/key.txt"

        tmp="$dir/.${vmName}.img.tmp"
        rm -f "$tmp"
        truncate -s 16M "$tmp"
        # Populate the filesystem from the staging dir without a loop mount.
        mke2fs -t ext4 -q -L "sops-${vmName}" -d "$stage" "$tmp"
        chown root:kvm "$tmp"
        chmod 0440 "$tmp"
        mv -f "$tmp" "$img"
        echo "built key image for ${vmName}"
      '';
    }) sopsVMs;
}
