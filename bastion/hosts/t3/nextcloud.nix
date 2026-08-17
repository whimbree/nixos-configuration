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
  nextcloudVersion = "32.0.1";
  mariadbVersion = "latest";
  redisVersion = "latest";
  collaboraVersion = "latest";
  notifyPushVersion = "latest";

  # Set to true to enable auto-updates
  enableAutoUpdate = false;

  # Nextcloud writes its application and audit streams only to JSON files.
  # Keep useful top-level fields, use the application message as the body, and
  # discard the raw URL and nested data map so query credentials and app-local
  # secret fields cannot leave the VM.
  nextcloudJsonLogOperators = [
    {
      type = "json_parser";
      parse_from = "body";
      parse_to = "attributes";
      on_error = "drop_quiet";
    }
    {
      type = "time_parser";
      parse_from = "attributes.time";
      layout_type = "gotime";
      layout = "2006-01-02T15:04:05Z07:00";
      on_error = "send_quiet";
    }
    {
      type = "move";
      from = "attributes.message";
      to = "body";
    }
    {
      type = "remove";
      field = "attributes.url";
    }
    {
      type = "remove";
      field = "attributes.data";
    }
  ];

  # The container's nginx uses the standard combined format. Parse only the
  # request path (never the query string or referrer), then replace the raw
  # line body with that sanitized path before export.
  nextcloudAccessLogOperators = [
    {
      type = "regex_parser";
      parse_from = "body";
      parse_to = "attributes";
      regex = ''^(?P<remote_addr>\S+) - \S+ \[(?P<time>[^\]]+)\] "(?P<method>\S+) (?P<path>[^?\s]+)(?:\?\S*)? (?P<protocol>[^"]+)" (?P<status>\d{3}) (?P<bytes>\d+) "[^"]*" "(?P<user_agent>[^"]*)"$'';
      on_error = "drop_quiet";
    }
    {
      type = "severity_parser";
      parse_from = "attributes.status";
      mapping = {
        info = [ "2xx" "3xx" ];
        warn = "4xx";
        error = "5xx";
      };
      on_error = "send_quiet";
    }
    {
      type = "time_parser";
      parse_from = "attributes.time";
      layout_type = "strptime";
      layout = "%d/%b/%Y:%H:%M:%S %z";
      on_error = "send_quiet";
    }
    {
      type = "copy";
      from = "attributes.path";
      to = "body";
    }
  ];
in {
  microvm = {
    mem = 2048;
    hotplugMem = 2048;
    vcpu = 4;

    shares = [
      {
        source = "/services/nextcloud";
        mountPoint = "/services/nextcloud";
        tag = "services-nextcloud";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/services/nextcloud";
        mountPoint = "/ocean/services/nextcloud";
        tag = "ocean-nextcloud";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
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

  systemd.services.podman-network-nextcloud = {
    description = "Create Nextcloud Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-nextcloud.service"
      "podman-nextcloud-mariadb.service"
      "podman-nextcloud-redis.service"
      "podman-nextcloud-collabora.service"
      "podman-nextcloud-notify_push.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists nextcloud || \
      ${pkgs.podman}/bin/podman network create nextcloud
    '';
  };

  # Auto-update timer (only active if enableAutoUpdate = true)
  systemd.timers.podman-auto-update-nextcloud = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-nextcloud = lib.mkIf enableAutoUpdate {
    description = "Auto-update Nextcloud containers";
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

  homelab.observabilityAgent = {
    supplementaryGroups = [ "fileshare" ];

    fileLogs = {
      nextcloud-app = {
        include = [ "/ocean/services/nextcloud/nextcloud.log" ];
        serviceName = "nextcloud";
        operators = nextcloudJsonLogOperators;
      };

      nextcloud-audit = {
        include = [ "/ocean/services/nextcloud/audit.log" ];
        serviceName = "nextcloud-audit";
        operators = nextcloudJsonLogOperators;
      };

      nextcloud-nginx-access = {
        include = [ "/services/nextcloud/config/log/nginx/access.log" ];
        serviceName = "nextcloud-nginx";
        operators = nextcloudAccessLogOperators;
      };
    };
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      nextcloud = {
        autoStart = true;
        image = "lscr.io/linuxserver/nextcloud:${nextcloudVersion}";
        volumes = [
          "/services/nextcloud/config:/config"
          "/ocean/services/nextcloud:/data"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        dependsOn = [ "nextcloud-mariadb" "nextcloud-redis" ];
        ports = [ "0.0.0.0:8080:80" ];
        extraOptions = [ "--network=nextcloud" ]
          ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      nextcloud-mariadb = {
        autoStart = true;
        image = "lscr.io/linuxserver/mariadb:${mariadbVersion}";
        volumes = [ "/services/nextcloud/mariadb:/config" ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
          MYSQL_ROOT_PASSWORD = "password";
          MYSQL_DATABASE = "nextcloud";
          MYSQL_USER = "nextcloud";
          MYSQL_PASSWORD = "nextcloud";
        };
        extraOptions = [
          "--network=nextcloud"
          "--health-cmd=nc -zv localhost 3306 || exit 1"
          "--health-interval=10s"
          "--health-retries=30"
          "--health-timeout=10s"
          "--health-start-period=10s"
        ];
        # Don't auto-update database - too risky
      };

      nextcloud-redis = {
        autoStart = true;
        image = "docker.io/redis:${redisVersion}";
        volumes = [ "/services/nextcloud/redis:/data" ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
        };
        cmd = [ "redis-server" "--requirepass" "nextcloud" ];
        extraOptions = [
          "--network=nextcloud"
          "--health-cmd=redis-cli -a nextcloud ping | grep PONG"
          "--health-interval=10s"
          "--health-retries=30"
          "--health-timeout=10s"
          "--health-start-period=10s"
        ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      nextcloud-collabora = {
        autoStart = true;
        image = "docker.io/collabora/code:${collaboraVersion}";
        environment = {
          extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
        };
        ports = [ "0.0.0.0:9980:9980" ];
        extraOptions = [ "--network=nextcloud" ]
          ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      nextcloud-notify_push = {
        autoStart = true;
        image = "ghcr.io/whimbree/notify_push:${notifyPushVersion}";
        volumes = [
          "/services/nextcloud/config/www/nextcloud/config/config.php:/config.php:ro"
        ];
        cmd = [ "/notify_push" "/config.php" ];
        environment = {
          NEXTCLOUD_URL = "http://nextcloud";
          DATABASE_URL =
            "mysql://nextcloud:nextcloud@nextcloud-mariadb:3306/nextcloud?ssl-mode=DISABLED";
        };
        dependsOn = [ "nextcloud" "nextcloud-mariadb" ];
        ports = [ "0.0.0.0:7867:7867" ];
        extraOptions = [ "--network=nextcloud" ]
          ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };
}
