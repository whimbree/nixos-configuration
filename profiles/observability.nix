{
  config,
  lib,
  observability,
  ...
}:
let
  hostName = config.networking.hostName;
in
{
  # Every physical host built through mkHost is an observability producer and
  # always uses the encrypted tailnet path.
  homelab.observabilityAgent = {
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

  virtualisation.containers.containersConf.settings.containers.log_driver =
    lib.mkDefault "journald";

  systemd.services.opentelemetry-collector = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  assertions = [
    {
      assertion = config.services.tailscale.enable;
      message = ''
        Physical host ${hostName} must enable Tailscale to reach the
        observability collector at ${observability.endpoints.tailnetOtlp}.
      '';
    }
  ];
}
