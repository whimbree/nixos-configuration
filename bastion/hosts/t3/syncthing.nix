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
  syncthingVersion = "latest";

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;

    shares = [
      {
        source = "/services/syncthing";
        mountPoint = "/services/syncthing";
        tag = "services-syncthing";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/merged/media/music";
        mountPoint = "/music";
        tag = "music";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 10; # 10GB cache
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
  systemd.timers.podman-auto-update-syncthing = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-syncthing = lib.mkIf enableAutoUpdate {
    description = "Auto-update Syncthing containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      syncthing = {
        autoStart = true;
        image = "lscr.io/linuxserver/syncthing:${syncthingVersion}";
        volumes = [ "/services/syncthing/config:/config" "/music:/music" ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        ports = [
          "0.0.0.0:8384:8384" # Web UI
          "0.0.0.0:22000:22000/tcp" # Listening port (TCP)
          "0.0.0.0:22000:22000/udp" # Listening port (UDP)
          "0.0.0.0:21027:21027/udp" # Protocol discovery
        ];
        extraOptions = [
          "--health-cmd=curl --fail localhost:8384 || exit 1"
          "--health-interval=10s"
          "--health-retries=30"
          "--health-timeout=10s"
          "--health-start-period=10s"
        ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };

  # Open firewall ports for Syncthing sync protocol
  networking.firewall = {
    allowedTCPPorts = [ 22000 ]; # Syncthing listening port
    allowedUDPPorts = [ 22000 21027 ]; # Syncthing listening + discovery
  };
}
