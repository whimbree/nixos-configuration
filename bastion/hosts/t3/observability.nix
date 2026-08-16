{
  config,
  lib,
  pkgs,
  vmName,
  mkVMNetworking,
  observability,
  ...
}:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };
in
{
  imports = [ ./observability-clickstack.nix ];

  microvm = {
    # hotplugMem is additional capacity in microvm.nix. Keep it available for
    # operator hotplug, but do not start with it already attached.
    mem = 8192;
    hotplugMem = 8192;
    hotpluggedMem = 0;
    vcpu = 4;
    balloon = true;
    shares = [
      # Defining any share replaces the mkDefault list from microvm-defaults,
      # so the ro-store share must be repeated here.
      {
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        tag = "ro-store";
        proto = "virtiofs";
      }
      {
        # Backup target only — never live database files (virtiofs is
        # explicitly forbidden for live ClickHouse data).
        source = observability.storage.backupHostPath;
        mountPoint = "/var/lib/observability-backup";
        tag = "obs-backup";
        proto = "virtiofs";
      }
    ];
    volumes = [
      {
        # Created and formatted by the operator; never auto-create a host file
        # when the zvol is absent. With autoCreate = false the size below is
        # documentation only — real capacity is the operator-set zvol volsize.
        image = observability.storage.clickhouseDevice;
        mountPoint = "/var/lib/clickhouse";
        label = "obs-clickhouse";
        size = 1024 * 256;
        fsType = "ext4";
        autoCreate = false;
        direct = true;
      }
      {
        image = "observability-app.img";
        mountPoint = "/var/lib/observability";
        label = "obs-app";
        size = 1024 * 16;
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "observability-collector.img";
        mountPoint = "/var/lib/clickstack-collector";
        label = "obs-collector";
        size = 1024 * 32;
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        label = "obs-containers";
        size = 1024 * 32;
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "tailscale-state.img";
        mountPoint = "/var/lib/tailscale";
        label = "obs-tailscale";
        size = 512;
        fsType = "ext4";
        autoCreate = true;
      }
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  fileSystems = {
    "/var/lib/clickhouse" = {
      options = [ "noatime" ];
      neededForBoot = true;
    };
    "/var/lib/observability" = {
      options = [ "noatime" ];
      neededForBoot = true;
    };
    "/var/lib/clickstack-collector" = {
      options = [ "noatime" ];
      neededForBoot = true;
    };
    "/var/lib/containers" = {
      options = [ "noatime" ];
      neededForBoot = true;
    };
    "/var/lib/tailscale" = {
      options = [ "noatime" ];
      neededForBoot = true;
    };
  };

  services.fstrim.enable = lib.mkForce true;

  sops.secrets."headscale-preauth-key" = { };

  # Keep tailnet enrollment independent from stack credential validation. The
  # key is checked without printing its value and only tailscale depends on it.
  systemd.services.headscale-key-ready = {
    description = "Validate observability Headscale pre-auth key";
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    before = [ "tailscaled-autoconnect.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    script = ''
      set -euo pipefail
      key_file=${lib.escapeShellArg config.sops.secrets."headscale-preauth-key".path}
      # Headscale 0.25.1 pre-auth keys are 24 random bytes encoded as exactly
      # 48 hexadecimal characters. Reject placeholders before a retry loop.
      if [[ $(wc -c <"$key_file") -ne 48 ]] || \
         ! grep -Eq '^[0-9A-Fa-f]{48}$' "$key_file"; then
        echo "Refusing an invalid Headscale pre-auth key file" >&2
        exit 1
      fi
    '';
  };

  services.tailscale.enable = true;
  services.tailscale.openFirewall = true;
  networking.firewall = {
    # These ports apply on every interface, including tailscale0 — which is
    # all the tailnet needs (wheatley OTLP push, private HyperDX bootstrap).
    # Deliberately no trustedInterfaces: the tailnet includes lower-trust VPN
    # guests, and they should reach exactly these ports, not everything.
    allowedTCPPorts = [
      22
      observability.ports.otlpGrpc
      observability.ports.hyperdx
    ];
    checkReversePath = "loose";
  };

  systemd.services.tailscaled-autoconnect = {
    description = "Enroll observability with Headscale without exposing the pre-auth key";
    after = [
      "tailscaled.service"
      "network-online.target"
      "headscale-key-ready.service"
      "var-lib-tailscale.mount"
    ];
    wants = [
      "tailscaled.service"
      "network-online.target"
    ];
    requires = [ "headscale-key-ready.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.jq
      pkgs.tailscale
    ];
    script = ''
      set -euo pipefail
      for _ in $(seq 1 60); do
        state=$(tailscale status --json --peers=false 2>/dev/null | jq -r '.BackendState // "Unknown"') || state=Unknown
        case "$state" in
          Running)
            exit 0
            ;;
          NeedsLogin|NeedsMachineAuth|Stopped)
            if tailscale up \
              --auth-key=file:${config.sops.secrets."headscale-preauth-key".path} \
              --hostname=${vmConfig.hostname} \
              --login-server=https://headscale.whimsical.cloud \
              --accept-dns=true; then
              exit 0
            fi
            ;;
        esac
        sleep 10
      done
      echo "Headscale enrollment did not reach Running state" >&2
      exit 1
    '';
  };
}
