# Scheduled `podman auto-update` for MicroVM guests, with image cleanup.
#
# Containers opt in with --label=io.containers.autoupdate=registry; this
# module only provides the schedule. bastion's container-auto-update-report
# (bastion/microvm-weekly-update.nix) reads the result of the unit below over
# SSH, so keep the unit name stable.
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.containerAutoUpdate;
  podman = lib.getExe config.virtualisation.podman.package;

  # auto-update pulls the new image but never deletes the one it replaced.
  # Pruning before the update guarantees room for the pull; pruning after
  # drops the image that was just superseded. `image prune` (unlike
  # `system prune`) leaves networks alone, so per-VM podman networks created
  # by oneshot units survive.
  pruneImages = "${podman} image prune --all --force";
in {
  options.homelab.containerAutoUpdate = {
    enable = lib.mkEnableOption "scheduled podman auto-update with image cleanup";

    timerConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      # After bastion's microvm-weekly-update (Wed 03:00 America/New_York),
      # so each week's pull runs on the freshly rebuilt guest config. Guests
      # are on UTC.
      default = {
        OnCalendar = "Wed *-*-* 10:00:00";
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
      description = "systemd timerConfig for container-auto-update.timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.virtualisation.podman.enable;
      message =
        "homelab.containerAutoUpdate requires virtualisation.podman.enable";
    }];

    systemd.services.container-auto-update = {
      description = "Update labelled podman containers and prune old images";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        ${pruneImages}
        rc=0
        ${podman} auto-update || rc=$?
        ${pruneImages}
        exit "$rc"
      '';
    };

    systemd.timers.container-auto-update = {
      wantedBy = [ "timers.target" ];
      inherit (cfg) timerConfig;
    };

    # Reclaims space after every boot, including the restart that follows
    # bastion's weekly rebuild, independent of the update schedule. Delayed
    # so container units have finished pulling and started; an image is only
    # removed once no container (running or stopped) references it.
    systemd.services.container-image-prune = {
      description = "Remove podman images not used by any container";
      serviceConfig.Type = "oneshot";
      script = pruneImages;
    };

    systemd.timers.container-image-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnBootSec = "15min";
    };
  };
}
