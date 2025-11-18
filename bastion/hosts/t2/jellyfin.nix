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
  jellyfinVersion = "10.10.7";

  # Set to true to enable auto-updates
  enableAutoUpdate = false;
in {
  microvm = {
    mem = 4096;
    hotplugMem = 8192;
    vcpu = 20;

    # Share VPN config from host
    shares = [
      {
        source = "/services/jellyfin/config";
        mountPoint = "/services/jellyfin/config";
        tag = "jellyfin";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/merged/media/shows";
        mountPoint = "/merged/media/shows";
        tag = "media-shows";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/movies";
        mountPoint = "/merged/media/movies";
        tag = "media-movies";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/music";
        mountPoint = "/merged/media/music";
        tag = "media-music";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/books";
        mountPoint = "/merged/media/books";
        tag = "media-books";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/xxx";
        mountPoint = "/merged/media/xxx";
        tag = "media-xxx";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
    ];

    volumes = [
      {
        image = "jellyfin-cache.img";
        mountPoint = "/var/cache/jellyfin";
        size = 1024 * 100; # 100GB cache
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        size = 1024 * 40; # 10GB cache
        fsType = "ext4";
        autoCreate = true;
      }
    ];
  };

  boot.kernelParams = [ "mitigations=off" ];

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
  systemd.timers.podman-auto-update-jellyfin = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-jellyfin = lib.mkIf enableAutoUpdate {
    description = "Auto-update jellyfin containers";
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
  users.groups.fileshare = {
    gid = 1420;
    members = [ "fileshare" ];
  };

  systemd.services.jellyfin-cache-permissions = {
    description = "Set permissions on Jellyfin cache";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      FOLDER=/var/cache/jellyfin

      # Change ownership recursively
      ${pkgs.coreutils}/bin/chown -R fileshare:fileshare "$FOLDER"

      # Change permissions
      ${pkgs.coreutils}/bin/chmod -R 770 "$FOLDER"
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      jellyfin = {
        autoStart = true;
        image = "lscr.io/linuxserver/jellyfin:${jellyfinVersion}";
        volumes = [
          "/services/jellyfin/config:/config"
          "/var/cache/jellyfin:/config/cache"
          "/merged/media/shows:/data/shows:ro"
          "/merged/media/movies:/data/movies:ro"
          "/merged/media/music:/data/music:ro"
          "/merged/media/books:/data/books:ro"
          "/merged/media/xxx:/data/xxx:ro"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        ports = [ "0.0.0.0:8096:8096" ];
        extraOptions = [
          # healthcheck
          "--health-cmd"
          "curl --fail localhost:8096 || exit 1"
          "--health-interval"
          "10s"
          "--health-retries"
          "30"
          "--health-timeout"
          "10s"
          "--health-start-period"
          "10s"
        ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };

  # Override firewall to allow Jellyfin
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
