{ lib }:
let
  vmLib = import ./bastion/lib/vm-lib.nix { inherit lib; };
  vm = vmLib.getVM "observability";

  # This is the complete rollout switchboard. Presence means enabled:
  # add/remove a host mapping or a MicroVM list item here, nowhere else.
  hostProducers = {
    bastion = "direct";
    wheatley = "tailnet";
  };
  microvmProducers = [
    "gateway"
    vm.hostname
  ];

  rollout = {
    hosts = hostProducers;
    microvms = microvmProducers;
    # Source IPs for the host-side OTLP firewall allow. The observability VM
    # reaches its own collector locally and never traverses the hypervisor
    # FORWARD chain, so it is excluded.
    microvmProducerIps = map (name: (vmLib.getVM name).ip) (
      lib.filter (name: name != vm.hostname) microvmProducers
    );
  };

  ports = {
    otlpGrpc = 4317;
    hyperdx = 8080;
  };

  tailnet = {
    domain = "whimsy.ts";
    host = "${vm.hostname}.${tailnet.domain}";
    hyperdxUrl = "http://${tailnet.host}:${toString ports.hyperdx}";
  };

  public = {
    # Flip only after the private-bootstrap gate in the activation runbook.
    enabled = false;
    domain = "bspwr.com";
    record = "splunk";
    host = "${public.record}.${public.domain}";
    hyperdxUrl = "https://${public.host}";
  };

  storage = {
    # Under rpool/safe by convention: this is the canonical log history, not
    # rebuildable data (rpool/local is for throwaway state). It sits as a
    # direct child of rpool/safe, deliberately OUTSIDE every recursive
    # znapzend plan — protection is application-level ClickHouse-native
    # backup (Phase 4), never live-zvol snapshots of merge-heavy data.
    clickhouseZvol = "rpool/safe/observability-clickhouse";
    clickhouseDevice = "/dev/zvol/${storage.clickhouseZvol}";
    # Application-consistent backups land on ocean — the second failure
    # domain (live data on rpool, copies on ocean). Storage tiering was
    # deliberately rejected to keep that separation clean.
    backupDataset = "ocean/backup/observability";
    backupHostPath = "/ocean/backup/observability";
  };

  endpoints = {
    directOtlp = "${vm.ip}:${toString ports.otlpGrpc}";
    tailnetOtlp = "${tailnet.host}:${toString ports.otlpGrpc}";
  };

  unknownMicrovms = lib.filter (name: !(builtins.hasAttr name vmLib.getAllVMs)) microvmProducers;
  invalidTransports = lib.filter (
    transport:
    !(builtins.elem transport [
      "direct"
      "tailnet"
    ])
  ) (builtins.attrValues hostProducers);
in
assert lib.assertMsg (
  unknownMicrovms == [ ]
) "Unknown observability MicroVM producers: ${lib.concatStringsSep ", " unknownMicrovms}";
assert lib.assertMsg (
  invalidTransports == [ ]
) "Observability host transports must be `direct` or `tailnet`";
{
  inherit
    vm
    rollout
    ports
    tailnet
    public
    storage
    endpoints
    ;
}
