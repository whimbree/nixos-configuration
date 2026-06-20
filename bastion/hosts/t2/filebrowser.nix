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
    mem = 512;
    hotplugMem = 1024; # headroom for 3 filebrowser instances + SD card indexing
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

    volumes = [
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        size = 1024 * 5; # 5GB cache
        fsType = "ext4";
        autoCreate = true;
      }
      {
        # Liz's Steam Deck SD card image, attached read-only as a raw disk.
        # mountPoint = null so microvm.nix does not auto-mount the whole disk;
        # the ext4 partition is mounted by UUID via fileSystems below.
        image = "/ocean/images/Liz_Steam_Deck_SDCard.img";
        imageType = "raw";
        readOnly = true;
        autoCreate = false;
        mountPoint = null;
        size = 976564; # required option; unused since autoCreate = false
        fsType = "ext4";
      }
    ];
  };

  # Mount partition 1 of the Steam Deck SD card image read-only. Identified by
  # filesystem UUID so it is independent of the virtio drive-letter ordering.
  fileSystems."/mnt/switch-sdcard" = {
    device = "/dev/disk/by-uuid/2041c36c-3f9b-4748-9dbc-3bc19d4c2f05";
    fsType = "ext4";
    options = [ "ro" "nofail" "x-systemd.device-timeout=30s" ];
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
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
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

      filebrowser-switch = {
        autoStart = true;
        image = "docker.io/filebrowser/filebrowser:${filebrowserVersion}";
        volumes = [
          "/mnt/switch-sdcard:/srv:ro"
          "/services/filebrowser/switch-config/filebrowser.db:/database/filebrowser.db"
          "/services/filebrowser/switch-config/settings.json:/config/settings.json"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        ports = [ "0.0.0.0:8082:80" ]; # Steam Deck SD card on port 8082
        extraOptions = lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };

  # Ensure the SD card mount is available before serving it.
  systemd.services.podman-filebrowser-switch.unitConfig.RequiresMountsFor =
    "/mnt/switch-sdcard";
}
