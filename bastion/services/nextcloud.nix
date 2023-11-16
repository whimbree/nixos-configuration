{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-nextcloud = {
    enable = true;
    description = "Create nextcloud docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-nextcloud" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create nextcloud || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."nextcloud" = {
    autoStart = true;
    image = "lscr.io/linuxserver/nextcloud:26.0.0";
    volumes = [
      "/services/nextcloud/config:/config"
      "/ocean/services/nextcloud:/data"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-nextcloud" ];
    extraOptions = [
      # networks
      "--network=nextcloud"
      # healthcheck
      "--health-cmd"
      "curl --fail --insecure https://localhost || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "2s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=nextcloud"
      "--label"
      "traefik.http.routers.nextcloud.rule=Host(`nextcloud.bspwr.com`)"
      "--label"
      "traefik.http.routers.nextcloud.priority=1"
      "--label"
      "traefik.http.routers.nextcloud.entrypoints=websecure"
      "--label"
      "traefik.http.routers.nextcloud.tls=true"
      "--label"
      "traefik.http.routers.nextcloud.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.nextcloud.service=nextcloud"
      "--label"
      "traefik.http.routers.nextcloud.middlewares=nextcloud_redirectregex, default@file"
      "--label"
      "traefik.http.services.nextcloud.loadbalancer.server.port=80"
      "--label"
      "traefik.http.middlewares.nextcloud_redirectregex.redirectregex.permanent=true"
      "--label"
      "traefik.http.middlewares.nextcloud_redirectregex.redirectregex.regex=https://(.*)/.well-known/(?:card|cal)dav"
      "--label"
      "traefik.http.middlewares.nextcloud_redirectregex.redirectregex.replacement=https://$${1}/remote.php/dav"
    ];
  };

  virtualisation.oci-containers.containers."nextcloud-mariadb" = {
    autoStart = true;
    image = "lscr.io/linuxserver/mariadb:latest";
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
    dependsOn = [ "create-network-nextcloud" ];
    extraOptions = [
      # networks
      "--network=nextcloud"
      # healthcheck
      "--health-cmd"
      "nc -zv localhost 3306 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "2s"
      "--health-start-period"
      "10s"
    ];
  };

  virtualisation.oci-containers.containers."nextcloud-collabora" = {
    autoStart = true;
    image = "docker.io/collabora/code:latest";
    environment = {
      extra_params = "--o:ssl.enable=false --o:ssl.termination=true";
    };
    dependsOn = [ "create-network-nextcloud" ];
    extraOptions = [
      # networks
      "--network=nextcloud"
      # healthcheck
      "--health-cmd"
      "curl --fail http://localhost:9980 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "2s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=nextcloud"
      "--label"
      "traefik.http.routers.collabora.rule=Host(`collabora.bspwr.com`)"
      "--label"
      "traefik.http.routers.collabora.entrypoints=websecure"
      "--label"
      "traefik.http.routers.collabora.tls=true"
      "--label"
      "traefik.http.routers.collabora.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.collabora.service=collabora"
      "--label"
      "traefik.http.routers.collabora.middlewares=default@file"
      "--label"
      "traefik.http.services.collabora.loadbalancer.server.port=9980"
    ];
  };

  virtualisation.oci-containers.containers."nextcloud-redis" = {
    autoStart = true;
    image = "docker.io/redis:latest";
    volumes = [ "/services/nextcloud/redis:/data" ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    cmd = [ "redis-server" "--requirepass" "nextcloud" ];
    dependsOn = [ "create-network-nextcloud" ];
    extraOptions = [
      # networks
      "--network=nextcloud"
      # healthcheck
      "--health-cmd"
      "redis-cli -a nextcloud ping | grep PONG"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "2s"
      "--health-start-period"
      "10s"
    ];
  };

  virtualisation.oci-containers.containers."nextcloud-notify_push" = {
    autoStart = true;
    image = "ghcr.io/whimbree/notify_push:latest";
    volumes = [
      "/services/nextcloud/config/www/nextcloud/config/config.php:/config.php:ro"
    ];
    cmd = [ "/notify_push" "/config.php" ];
    environment = { NEXTCLOUD_URL = "http://nextcloud"; };
    dependsOn = [ "create-network-nextcloud" ];
    extraOptions = [
      # networks
      "--network=nextcloud"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=nextcloud"
      "--label"
      "traefik.http.routers.nextcloud-client-push.rule=Host(`nextcloud.bspwr.com`) && PathPrefix(`/push`)"
      "--label"
      "traefik.http.routers.nextcloud-client-push.priority=2"
      "--label"
      "traefik.http.routers.nextcloud-client-push.entrypoints=websecure"
      "--label"
      "traefik.http.routers.nextcloud-client-push.tls=true"
      "--label"
      "traefik.http.routers.nextcloud-client-push.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.nextcloud-client-push.service=nextcloud-client-push"
      "--label"
      "traefik.http.services.nextcloud-client-push.loadbalancer.server.port=7867"
      "--label"
      "traefik.http.routers.nextcloud-client-push.middlewares=nextcloud-client-push_strip,default@file"
      "--label"
      "traefik.http.middlewares.nextcloud-client-push_strip.stripprefix.prefixes=/push"
    ];
  };
}
