# Deterministic per-MicroVM age keys, derived on the host from one shared seed.
#
# secrets/microvm-key-seed.yaml is decrypted (via bastion's ssh-derived age key)
# to /run/secrets/microvm-key-seed. For every VM flagged `sops = true` in
# vm-registry.nix a derive-vm-key-<vm>.service builds
# /persist/etc/sops/vm-keys/<vm>.img, holding the HKDF-derived age identity, just
# before microvm@<vm>.service starts. Because derivation is deterministic, a
# lost/deleted image rebuilds to the same identity (self-heal); only the single
# seed needs backing up.
#
# See docs/sops-microvm-key-image.md.
{ lib, pkgs, inputs, ... }:
let
  vmLib = import ../lib/vm-lib.nix { inherit lib; };
  sopsVMs = lib.filterAttrs (_n: v: v.sops or false) vmLib.getAllVMs;

  # Wraps the shared derivation helper. Reads the base64 seed on stdin, prints
  # the age identity (or --pub for the recipient).
  deriveAgeKey = pkgs.writeShellApplication {
    name = "derive-age-key";
    runtimeInputs = [ pkgs.python3 pkgs.age ];
    text = ''exec python3 ${../lib/derive-age-key.py} "$@"'';
  };

  # Convenience for authoring on bastion: derive a VM's pubkey from the already
  # decrypted seed (bastion is a recipient of microvm-key-seed.yaml). On a
  # workstation without /run/secrets, use scripts/sops-vm-pubkey (decrypts via sops).
  sopsVmPubkey = pkgs.writeShellApplication {
    name = "sops-vm-pubkey";
    runtimeInputs = [ deriveAgeKey ];
    text = ''
      vm="''${1:?usage: sops-vm-pubkey <vm>}"
      derive-age-key --pub "$vm" < /run/secrets/microvm-key-seed
    '';
  };
in {
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # Install secrets via a systemd unit so the derive units below can order
  # cleanly after it.
  sops.useSystemdActivation = true;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.microvm-key-seed.sopsFile = ../../secrets/microvm-key-seed.yaml;

  environment.systemPackages = [ deriveAgeKey sopsVmPubkey ];

  systemd.services = lib.mapAttrs' (vmName: _vm:
    lib.nameValuePair "derive-vm-key-${vmName}" {
      description = "Derive + build sops age key image for MicroVM ${vmName}";
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
      before = [ "microvm@${vmName}.service" ];
      requiredBy = [ "microvm@${vmName}.service" ];
      unitConfig.RequiresMountsFor = "/persist";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ deriveAgeKey pkgs.e2fsprogs pkgs.coreutils ];
      script = ''
        set -euo pipefail
        img=/persist/etc/sops/vm-keys/${vmName}.img
        dir=$(dirname "$img")
        install -d -m 0750 -o root -g kvm "$dir"

        want=$(derive-age-key ${vmName} < /run/secrets/microvm-key-seed)

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
