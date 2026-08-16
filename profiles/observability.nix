{
  config,
  lib,
  observability,
  ...
}:
let
  hostName = config.networking.hostName;
  enabled = observability.enable
    && (observability.rollout.activateFleet
      || config.homelab.observabilityRolloutActivated);
in
{
  options.homelab.observabilityRolloutActivated = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Temporary per-host Phase 2 activation fence. Remove this option and its
      host settings after the fleet rollout is complete.
    '';
  };

  config = {
    # Every physical host built through mkHost is eligible. Until the Phase 2
    # fleet flip, only locally activated hosts run the agent. Transport is
    # always the encrypted tailnet path.
    homelab.observabilityAgent = lib.mkIf enabled {
      enable = true;
      endpoint = observability.endpoints.tailnetOtlp;
      nodeKind = "host";
      journalMaxUse = "6G";
      # Per-signal ceiling, above the measured 72-hour p99 of ~3.4 GiB
      # serialized bastion journal output; lives on the host's persistent
      # /var/log dataset, which has ample headroom for two queues.
      queueMaxMiB = 4096;
      memoryLimitMiB = 256;
    };

    virtualisation.containers.containersConf.settings.containers.log_driver = lib.mkIf enabled (
      lib.mkDefault "journald"
    );

    systemd.services.opentelemetry-collector = lib.mkIf enabled {
      after = [ "tailscaled.service" ];
      wants = [ "tailscaled.service" ];
    };

    assertions = [
      {
        assertion = !enabled || config.services.tailscale.enable;
        message = ''
          Physical host ${hostName} must enable Tailscale to reach the
          observability collector at ${observability.endpoints.tailnetOtlp}.
        '';
      }
    ];
  };
}
