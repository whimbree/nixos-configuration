{ config, lib, pkgs, ... }:
# A send-only account other hosts pull ZFS copies from with syncoid.
#
# Each client key may only run read-only `zfs list`/`zfs get` and `zfs send`
# of snapshots under the configured datasets, and only from its own address.
# ZFS delegation is the second fence: the account holds only the "send"
# permission, on those datasets.
let
  cfg = config.homelab.syncoidSend;
  zfs = "${config.boot.zfs.package}/bin/zfs";

  sendable = "^(${lib.concatMapStringsSep "|" lib.escapeRegex cfg.datasets})(/[^@]+)?@[^@]+$";

  filter = pkgs.writeShellScript "syncoid-send-filter" ''
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

    flags='^-[LceinvPI]+$'
    sendable=${lib.escapeShellArg sendable}
    [ "''${#args[@]}" -ge 2 ] && [ "''${args[0]}" = zfs ] || deny
    case "''${args[1]}" in
      list | get) ;;
      send)
        for arg in "''${args[@]:2}"; do
          [[ "$arg" =~ $flags ]] || [[ "$arg" =~ $sendable ]] || deny
        done
        ;;
      *) deny ;;
    esac
    exec ${zfs} "''${args[@]:1}"
  '';
in {
  options.homelab.syncoidSend = {
    enable = lib.mkEnableOption "the send-only syncoid-send account";

    datasets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "rpool/safe" ];
      description = "Datasets whose snapshots, and their children's, may be sent.";
    };

    clients = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          key = lib.mkOption {
            type = lib.types.str;
            description = "The client's SSH public key.";
          };
          address = lib.mkOption {
            type = lib.types.str;
            description = ''
              The only address the key is accepted from. Use the Tailscale
              IPv4 address: names can also resolve to IPv6.
            '';
          };
        };
      });
      description = "Hosts allowed to pull, by name.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: client: {
      assertion = lib.hasPrefix "ssh-ed25519 " client.key;
      message = "homelab.syncoidSend.clients.${name}.key: set it to ${name}'s syncoid public key";
    }) cfg.clients;

    users.users.syncoid-send = {
      isSystemUser = true;
      group = "syncoid-send";
      home = "/var/empty";
      shell = pkgs.bash; # sshd runs the forced command through the login shell
      openssh.authorizedKeys.keys = lib.mapAttrsToList (_: client:
        ''restrict,from="${client.address}",command="${filter}" ${client.key}'')
        cfg.clients;
    };
    users.groups.syncoid-send = { };

    systemd.services.syncoid-send-allow = {
      description = "Let syncoid-send send ${lib.concatStringsSep ", " cfg.datasets}";
      wantedBy = [ "multi-user.target" ];
      after = [ "zfs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = map (d: "${zfs} allow -u syncoid-send send ${d}") cfg.datasets;
      };
    };
  };
}
