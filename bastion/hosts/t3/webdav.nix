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
  webdavVersion = "latest";

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    mem = 512;
    hotplugMem = 1024;
    vcpu = 2;

    shares = [
      {
        source = "/services/webdav";
        mountPoint = "/services/webdav";
        tag = "services-webdav";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/backup/duplicati";
        mountPoint = "/ocean/backup/duplicati";
        tag = "ocean-duplicati";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 5; # 5GB cache
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
  systemd.timers.podman-auto-update-webdav = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00"; # Sunday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-webdav = lib.mkIf enableAutoUpdate {
    description = "Auto-update WebDAV containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      webdav-alex-duplicati = {
        autoStart = true;
        image = "docker.io/dgraziotin/nginx-webdav-nononsense:${webdavVersion}";
        volumes = [
          "/ocean/backup/duplicati/alex:/data"
          "/services/webdav/alex-duplicati-config:/config"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
          SERVER_NAMES = "localhost";
          TIMEOUTS_S = "3600"; # 1 hour timeout for large backups
          CLIENT_MAX_BODY_SIZE = "10G";
        };
        ports = [ "0.0.0.0:8080:80" ];
        extraOptions = [
          "--health-cmd=curl localhost:80 || exit 1"
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
