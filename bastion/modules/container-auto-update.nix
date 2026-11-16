# Scheduled `podman auto-update` for MicroVM guests, with image cleanup and
# ntfy notifications.
#
# Containers opt in with --label=io.containers.autoupdate=registry; this
# module only provides the schedule. bastion's container-auto-update-report
# (bastion/microvm-weekly-update.nix) also reads the result of the unit below
# over SSH as a safety net for guests that stop reporting, so keep the unit
# name stable.
{ config, lib, pkgs, vmName, ... }:
let
  cfg = config.homelab.containerAutoUpdate;
  vmLib = import ../lib/vm-lib.nix { inherit lib; };
  podman = lib.getExe config.virtualisation.podman.package;
  host = config.networking.hostName;

  # auto-update pulls the new image but never deletes the one it replaced.
  # Pruning before the update guarantees room for the pull; pruning after
  # drops the image that was just superseded. `image prune` (unlike
  # `system prune`) leaves networks alone, so per-VM podman networks created
  # by oneshot units survive.
  pruneImages = "${podman} image prune --all --force";

  notify = pkgs.writeShellApplication {
    name = "container-auto-update-notify";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      # usage: container-auto-update-notify <title> <priority> <tags>; body on stdin
      curl -fsS --retry 3 --max-time 30 -o /dev/null \
        -H "Authorization: Bearer $(<${config.sops.secrets.ntfy_token.path})" \
        -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
        --data-binary @- \
        https://ntfy.whimsical.cloud/monitoring
    '';
  };
in {
  options.homelab.containerAutoUpdate = {
    enable = lib.mkEnableOption "scheduled podman auto-update with image cleanup";

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Send ntfy notifications for failures (once until recovery), recovery,
        and container updates. Needs `sops = true` for the VM in
        vm-registry.nix and `ntfy_token` in secrets/bastion/<vm>.yaml.
      '';
    };

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

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.virtualisation.podman.enable;
          message =
            "homelab.containerAutoUpdate requires virtualisation.podman.enable";
        }
        {
          assertion = cfg.notify -> (vmLib.getAllVMs.${vmName}.sops or false);
          message = ''
            homelab.containerAutoUpdate.notify on ${vmName} needs `sops = true`
            in bastion/vm-registry.nix (for the ntfy token), or set notify = false.
          '';
        }
      ];

      systemd.services.container-auto-update = {
        description = "Update labelled podman containers and prune old images";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.gawk ];
        serviceConfig = {
          Type = "oneshot";
          # Lives on the guest's tmpfs: failure suppression resets on reboot,
          # so a still-broken update is re-announced once per boot.
          StateDirectory = "container-auto-update";
        };
        script = ''
          ${pruneImages}
          rc=0
          out=$(${podman} auto-update 2>&1) || rc=$?
          printf '%s\n' "$out"
          ${pruneImages}
        '' + lib.optionalString cfg.notify ''
          failing="$STATE_DIRECTORY/failing"
          if (( rc != 0 )); then
            if [[ ! -e "$failing" ]]; then
              tail -n 15 <<<"$out" | ${lib.getExe notify} \
                "${host}: container auto-update failed" high rotating_light \
                || echo "ntfy notification failed" >&2
              touch "$failing"
            fi
          else
            if [[ -e "$failing" ]]; then
              echo "podman auto-update succeeded again" | ${lib.getExe notify} \
                "${host}: container auto-update recovered" default white_check_mark \
                || echo "ntfy notification failed" >&2
              rm -f "$failing"
            fi
            # UPDATED is the last column of the auto-update table.
            updated=$(awk '$NF == "true" { print $1 }' <<<"$out")
            if [[ -n "$updated" ]]; then
              ${lib.getExe notify} \
                "${host}: containers updated" low arrows_counterclockwise \
                <<<"$updated" || echo "ntfy notification failed" >&2
            fi
          fi
        '' + ''
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
    }

    (lib.mkIf cfg.notify {
      sops.secrets.ntfy_token = { };
      systemd.services.container-auto-update.after =
        [ "sops-install-secrets.service" ];
    })
  ]);
}
