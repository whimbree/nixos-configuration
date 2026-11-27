{ config, pkgs, lib, ... }:
let
  # bastion pulls copies of rpool/safe/* over Tailscale with this key; its
  # private half is bastion:/persist/var/lib/syncoid/wheatley_ed25519.
  bastionSyncoidKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZPIWWqQmirTyq4oKMOEbwJ+MI2zQ/E3gob6EkGbmfC syncoid@bastion";
  bastionTailscaleIp = "100.64.0.4";

  # The only commands the key may run: read-only zfs list/get, and zfs send of
  # snapshots under rpool/safe. ZFS delegation (below) is the second fence.
  sendFilter = pkgs.writeShellScript "syncoid-send-filter" ''
    set -euo pipefail
    cmd=''${SSH_ORIGINAL_COMMAND-}
    deny() {
      echo "syncoid-send: refused: $cmd" >&2
      ${pkgs.util-linux}/bin/logger -t syncoid-send -- "refused: $cmd" || true
      exit 1
    }

    case "$cmd" in
      # syncoid's control connection and its echo test, and its probes for
      # tools we don't offer
      exit | "echo -n") exit 0 ;;
      "command -v "*) exit 1 ;;
      # Nothing but words and single quotes: no shell syntax to evaluate.
      "" | *[!A-Za-z0-9\ \'@/_:.,=+-]*) deny ;;
    esac
    eval "args=($cmd)"

    [ "''${#args[@]}" -ge 2 ] && [ "''${args[0]}" = zfs ] || deny
    case "''${args[1]}" in
      list | get) ;;
      send)
        for arg in "''${args[@]:2}"; do
          [[ "$arg" =~ ^-[LceinvPI]+$ ]] ||
            [[ "$arg" =~ ^rpool/safe/[^@]+@[^@]+$ ]] || deny
        done
        ;;
      *) deny ;;
    esac
    exec ${config.boot.zfs.package}/bin/zfs "''${args[@]:1}"
  '';
in {
  assertions = [{
    assertion = lib.hasPrefix "ssh-ed25519 " bastionSyncoidKey;
    message = "wheatley/backup.nix: set bastionSyncoidKey to bastion's syncoid public key";
  }];

  services.zfs = {
    # enable automatic scrubbing
    autoScrub = {
      enable = true;
      pools = [ "rpool" ];
      interval = "Mon, 02:00";
    };
  };

  # Local snapshots. Retention is shared: modules/snapshot-policy.nix.
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets = {
      "rpool/safe/home".useTemplate = [ "important" ];
      "rpool/safe/persist".useTemplate = [ "important" ];
      "rpool/safe/services".useTemplate = [ "important" ];
    };
  };

  # Send-only account for bastion's pull (bastion/replication.nix). It can't
  # get a shell, forward ports, or create, change or destroy anything.
  users.users.syncoid-send = {
    isSystemUser = true;
    group = "syncoid-send";
    home = "/var/empty";
    # sshd runs the forced command through the login shell.
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      ''restrict,from="${bastionTailscaleIp}",command="${sendFilter}" ${bastionSyncoidKey}''
    ];
  };
  users.groups.syncoid-send = { };

  # Delegations live in the pool; set them on every boot so they match this.
  systemd.services.syncoid-send-allow = {
    description = "Let syncoid-send send rpool/safe";
    wantedBy = [ "multi-user.target" ];
    after = [ "zfs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart =
        "${config.boot.zfs.package}/bin/zfs allow -u syncoid-send send rpool/safe";
    };
  };
}
