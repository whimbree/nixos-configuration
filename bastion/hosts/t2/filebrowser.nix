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
  filebrowserVersion = "s6";

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    mem = 1024;
    hotplugMem = 1024;
    vcpu = 2;

    shares = [
      {
        source = "/services/filebrowser";
        mountPoint = "/services/filebrowser";
        tag = "services-filebrowser";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/downloads";
        mountPoint = "/ocean/downloads";
        tag = "ocean-downloads";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media";
        mountPoint = "/merged/media";
        tag = "merged-media";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
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
  systemd.timers.podman-auto-update-filebrowser = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00"; # Sunday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-filebrowser = lib.mkIf enableAutoUpdate {
    description = "Auto-update FileBrowser containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  # create fileshare user for services
  users.users.fileshare = {
    createHome = false;
    isSystemUser = true;
    group = "fileshare";
    uid = 1420;
  };
  users.groups.fileshare.gid = 1420;

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      filebrowser-downloads = {
        autoStart = true;
        image = "docker.io/filebrowser/filebrowser:${filebrowserVersion}";
        volumes = [
          "/ocean/downloads:/srv:ro"
          "/services/filebrowser/downloads-config/filebrowser.db:/database/filebrowser.db"
          "/services/filebrowser/downloads-config/settings.json:/config/settings.json"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        ports = [ "0.0.0.0:8080:80" ]; # Downloads on port 8080
        extraOptions = lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      filebrowser-media = {
        autoStart = true;
        image = "docker.io/filebrowser/filebrowser:${filebrowserVersion}";
        volumes = [
          "/merged/media/shows:/srv/shows:ro"
          "/merged/media/movies:/srv/movies:ro"
          "/merged/media/music:/srv/music:ro"
          "/merged/media/books:/srv/books:ro"
          "/services/filebrowser/media-config/filebrowser.db:/database/filebrowser.db"
          "/services/filebrowser/media-config/settings.json:/config/settings.json"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        ports = [ "0.0.0.0:8081:80" ]; # Media on port 8081
        extraOptions = lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };
}
