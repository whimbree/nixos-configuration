{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-photoprism = {
    enable = true;
    description = "Create photoprism docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-photoprism" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create photoprism || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."photoprism" = {
    autoStart = true;
    image = "docker.io/photoprism/photoprism:latest";
    volumes = [
      "/services/photoprism/storage:/photoprism/storage"
      "/ocean/services/nextcloud/bree/files/Camera:/photoprism/originals:ro"
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
    dependsOn = [ "create-network-photoprism" "photoprism-mariadb" ];
    extraOptions = [
      # networks
      "--network=photoprism"
      # labels
      ## ofelia
      "--label"
      "ofelia.enabled=true"
      "--label"
      "ofelia.job-exec.photoprism_index.schedule='@every 1h'"
      "--label"
      "ofelia.job-exec.photoprism_index.command='photoprism index --cleanup'"
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=photoprism"
      "--label"
      "traefik.http.routers.photoprism.rule=Host(`photoprism.bspwr.com`)"
      "--label"
      "traefik.http.routers.photoprism.entrypoints=websecure"
      "--label"
      "traefik.http.routers.photoprism.tls=true"
      "--label"
      "traefik.http.routers.photoprism.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.photoprism.service=photoprism"
      "--label"
      "traefik.http.routers.photoprism.middlewares=default@file"
      "--label"
      "traefik.http.services.photoprism.loadbalancer.server.port=2342"
    ];
  };

  virtualisation.oci-containers.containers."photoprism-mariadb" = {
    autoStart = true;
    image = "docker.io/mariadb:10.6";
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
    dependsOn = [ "create-network-photoprism" ];
    extraOptions = [
      # networks
      "--network=photoprism"
    ];
  };

  # docker job scheduler
  virtualisation.oci-containers.containers."photoprism-ofelia" = {
    autoStart = true;
    image = "docker.io/mcuadros/ofelia:latest";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    cmd = [ "daemon" "--docker" ];
    dependsOn = [ "photoprism" ];
  };
}
