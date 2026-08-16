{ lib }:
let
  vmLib = import ./bastion/lib/vm-lib.nix { inherit lib; };
  vm = vmLib.getVM "observability";

  # Global producer gate. Physical hosts consume this through their shared
  # profile; MicroVMs additionally honor their registry `observability` flag.
  enable = true;

  # Temporary Phase 2 fence. One true flip activates every eligible registry
  # VM and every mkHost physical host; remove the fence after rollout.
  rollout.activateFleet = false;

  eligibleVMs = vmLib.getObservedVMs;
  activeVMs = if enable then
    lib.filterAttrs (_name: producer:
      rollout.activateFleet || producer.rolloutActivated) eligibleVMs
  else { };
  remoteEligibleVMs = lib.filterAttrs
    (_name: producer: producer.hypervisor != vm.hypervisor) eligibleVMs;
  directActiveVMs = lib.filterAttrs (name: producer:
    name != vm.hostname && producer.hypervisor == vm.hypervisor) activeVMs;

  producers = {
    eligibleMicrovms = builtins.attrNames eligibleVMs;
    activeMicrovms = builtins.attrNames activeVMs;
    # Only active co-located producers traverse this hypervisor's FORWARD
    # chain. The observability VM reaches its collector locally and is excluded.
    directMicrovmIps = map (producer: producer.ip)
      (builtins.attrValues directActiveVMs);
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

  remoteProducerDescriptions = lib.mapAttrsToList
    (name: producer: "${name} (${producer.hypervisor})") remoteEligibleVMs;
in
assert lib.assertMsg (vm.hypervisor == "bastion") ''
  The observability VM must remain on hypervisor `bastion` until host
  placement and firewall generation support another collector hypervisor.
'';
assert lib.assertMsg (
  remoteProducerDescriptions == [ ]
) ''
  Observability-eligible MicroVMs must be co-located with the observability VM on
  hypervisor `${vm.hypervisor}` because no remote OTLP relay exists yet.
  Remote producers: ${lib.concatStringsSep ", " remoteProducerDescriptions}
'';
{
  inherit
    enable
    rollout
    vm
    producers
    ports
    tailnet
    public
    storage
    endpoints
    ;
}
