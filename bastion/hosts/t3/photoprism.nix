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
  photoprismVersion = "latest";
  mariadbVersion = "10.6";

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    mem = 2048;
    hotplugMem = 2048;
    vcpu = 4;

    shares = [
      {
        source = "/services/photoprism";
        mountPoint = "/services/photoprism";
        tag = "services-photoprism";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/services/nextcloud/bree/files/Camera";
        mountPoint = "/ocean/photos";
        tag = "ocean-photos";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
    ];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 40; # 40GB cache
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

  systemd.services.podman-network-photoprism = {
    description = "Create PhotoPrism Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-photoprism.service"
      "podman-photoprism-mariadb.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists photoprism || \
      ${pkgs.podman}/bin/podman network create photoprism
    '';
  };

  # Auto-update timer (only active if enableAutoUpdate = true)
  systemd.timers.podman-auto-update-photoprism = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-photoprism = lib.mkIf enableAutoUpdate {
    description = "Auto-update PhotoPrism containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  # PhotoPrism indexing timer - runs hourly
  systemd.timers.photoprism-index = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  systemd.services.photoprism-index = {
    description = "PhotoPrism index and cleanup";
    after = [ "podman-photoprism.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${pkgs.podman}/bin/podman exec photoprism photoprism index --cleanup
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      photoprism = {
        autoStart = true;
        image = "docker.io/photoprism/photoprism:${photoprismVersion}";
        volumes = [
          "/services/photoprism/storage:/photoprism/storage"
          "/ocean/photos:/photoprism/originals:ro"
        ];
        environment = {
          PHOTOPRISM_ADMIN_NAME = "bree";
          PHOTOPRISM_ADMIN_PASSWORD = "insecure";
          PHOTOPRISM_SITE_URL = "https://photoprism.bspwr.com";
          PHOTOPRISM_DATABASE_DRIVER = "mysql";
          PHOTOPRISM_DATABASE_SERVER = "photoprism-mariadb:3306";
          PHOTOPRISM_DATABASE_NAME = "photoprism";
          PHOTOPRISM_DATABASE_USER = "photoprism";
          PHOTOPRISM_DATABASE_PASSWORD = "photoprism";
          PHOTOPRISM_SITE_TITLE = "PhotoPrism";
          PHOTOPRISM_SITE_CAPTION = "Browse Your Life";
          PHOTOPRISM_SITE_DESCRIPTION = "";
          PHOTOPRISM_SITE_AUTHOR = "";
          PHOTOPRISM_READONLY = "true";
          PHOTOPRISM_SPONSOR = "true";
          HOME = "/photoprism";
        };
        workdir = "/photoprism";
        dependsOn = [ "photoprism-mariadb" ];
        ports = [ "0.0.0.0:2342:2342" ];
        extraOptions = [ "--network=photoprism" ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      photoprism-mariadb = {
        autoStart = true;
        image = "docker.io/mariadb:${mariadbVersion}";
        volumes = [ "/services/photoprism/mariadb:/var/lib/mysql" ];
        cmd = [
          "mysqld"
          "--innodb-buffer-pool-size=256M"
          "--transaction-isolation=READ-COMMITTED"
          "--character-set-server=utf8mb4"
          "--collation-server=utf8mb4_unicode_ci"
          "--max-connections=512"
          "--innodb-rollback-on-timeout=OFF"
          "--innodb-lock-wait-timeout=120"
        ];
        environment = {
          MYSQL_ROOT_PASSWORD = "photoprism";
          MYSQL_DATABASE = "photoprism";
          MYSQL_USER = "photoprism";
          MYSQL_PASSWORD = "photoprism";
        };
        extraOptions = [
          "--network=photoprism"
          "--health-cmd=mysqladmin ping -h localhost -u root -pphotoprism || exit 1"
          "--health-interval=30s"
          "--health-retries=3"
          "--health-timeout=10s"
          "--health-start-period=30s"
        ];
        # Don't auto-update database - too risky
      };
    };
  };
}
