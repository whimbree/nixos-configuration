{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Version pinning - change these to update
  blogVersion = "latest";

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    mem = 1024;
    hotplugMem = 1024;
    vcpu = 2;

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 2; # 2GB cache
      fsType = "ext4";
      autoCreate = true;
    }];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Auto-update timer (only active if enableAutoUpdate = true)
  systemd.timers.podman-auto-update-blog = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-blog = lib.mkIf enableAutoUpdate {
    description = "Auto-update blog containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      blog = {
        autoStart = true;
        image = "ghcr.io/whimbree/blog:${blogVersion}";
        ports = [
          "0.0.0.0:80:80"
        ];
        extraOptions = [
          "--health-cmd=curl --fail localhost:80 || exit 1"
          "--health-interval=10s"
          "--health-retries=30"
          "--health-timeout=10s"
          "--health-start-period=10s"
        ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };
}
