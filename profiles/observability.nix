{
  config,
  lib,
  observability,
  ...
}:
let
  hostName = config.networking.hostName;
  transport = observability.rollout.hosts.${hostName} or null;
  enabled = transport != null;
  endpoint =
    if transport == "tailnet" then
      observability.endpoints.tailnetOtlp
    else
      observability.endpoints.directOtlp;
in
{
  # A host is a producer when it appears in observability.rollout.hosts.
  homelab.observabilityAgent = lib.mkIf enabled {
    enable = true;
    inherit endpoint;
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

  systemd.services.opentelemetry-collector = lib.mkIf (transport == "tailnet") {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  assertions = [
    {
      assertion = !enabled || transport != "tailnet" || config.services.tailscale.enable;
      message = ''
        Physical host ${hostName} must enable Tailscale to reach the
        observability collector at ${observability.endpoints.tailnetOtlp}.
      '';
    }
    {
      assertion =
        !enabled
        || transport != "direct"
        || lib.hasAttrByPath [ "microvm" "vms" observability.vm.hostname ] config;
      message = ''
        Physical host ${hostName} selects direct observability transport but
        does not host the ${observability.vm.hostname} MicroVM.
      '';
    }
  ];
}
