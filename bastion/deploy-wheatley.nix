{ config, pkgs, lib, ... }:
# Nightly: build wheatley's system from the repo's main branch here and push
# it with deploy-rs (deploy.nodes.wheatley in flake.nix). wheatley has one
# CPU and can't compile its own system while serving traffic.
#
# If the new system leaves wheatley unreachable over SSH, wheatley rolls
# itself back and this unit fails, which sends an ntfy alert. New kernels
# take effect only after a manual reboot of wheatley.
#
# One-time setup, on bastion (before or after switching to this config):
#   sudo install -d -m 700 /persist/var/lib/wheatley-deploy
#   sudo ssh-keygen -t ed25519 -N "" -C deploy@bastion \
#     -f /persist/var/lib/wheatley-deploy/id_ed25519
# and put the .pub line in wheatley/deploy.nix.
let
  home = "/persist/var/lib/wheatley-deploy";
in {
  users.users.wheatley-deploy = {
    isSystemUser = true;
    group = "wheatley-deploy";
    inherit home;
  };
  users.groups.wheatley-deploy = { };
  # Z: the key may have been made by root before this account existed.
  systemd.tmpfiles.rules = [
    "d ${home} 0700 wheatley-deploy wheatley-deploy -"
    "Z ${home} - wheatley-deploy wheatley-deploy -"
  ];

  systemd.services.deploy-wheatley = {
    description = "Build wheatley's system and push it with deploy-rs";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.deploy-rs config.nix.package pkgs.git pkgs.openssh ];
    environment = {
      HOME = home;
      DEPLOY_FLAKE = "github:whimbree/nixos-configuration";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "wheatley-deploy";
      Group = "wheatley-deploy";
      WorkingDirectory = home;
      TimeoutStartSec = "2h";
    };
    # --skip-checks: don't evaluate the whole flake's checks first.
    # Nix re-fetches the github: ref once its cached copy is over an hour
    # old (tarball-ttl), so each nightly run sees the current main.
    script = ''
      exec deploy --skip-checks \
        --ssh-opts "-i ${home}/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes" \
        "$DEPLOY_FLAKE#wheatley"
    '';
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
  };

  # After bastion's own 04:00 upgrade.
  systemd.timers.deploy-wheatley = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 05:00:00";
  };
}
