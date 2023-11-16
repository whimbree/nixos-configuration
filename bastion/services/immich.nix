{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-immich = {
    enable = true;
    description = "Create immich docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-immich" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create immich || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."immich-server" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-server:release";
    cmd = [ "start.sh" "immich" ];
    volumes = [
      "/ocean/services/immich/upload:/usr/src/app/upload"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [
      "create-network-immich"
      "immich-redis"
      "immich-postgres"
      "immich-typesense"
    ];
    extraOptions = [
      # networks
      "--network=immich"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=immich"
      "--label"
      "traefik.http.routers.immich-api.rule=Host(`immich.bspwr.com`) && Pathprefix(`/api`)"
      "--label"
      "traefik.http.middlewares.service-immich-api-strip.stripprefix.prefixes=/api"
      "--label"
      "traefik.http.routers.immich-api.middlewares=service-immich-api-strip, default@file"
      "--label"
      "traefik.http.routers.immich-api.entrypoints=websecure"
      "--label"
      "traefik.http.routers.immich-api.tls=true"
      "--label"
      "traefik.http.routers.immich-api.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.immich-api.service=immich-api"
      "--label"
      "traefik.http.services.immich-api.loadbalancer.server.port=3001"
    ];
  };

  virtualisation.oci-containers.containers."immich-microservices" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-server:release";
    cmd = [ "start.sh" "microservices" ];
    volumes = [
      "/ocean/services/immich/upload:/usr/src/app/upload"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [
      "create-network-immich"
      "immich-redis"
      "immich-postgres"
      "immich-typesense"
    ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  virtualisation.oci-containers.containers."immich-machine-learning" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-machine-learning:release";
    volumes = [ "/services/immich/model-cache:/cache" ];
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  virtualisation.oci-containers.containers."immich-web" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-web:release";
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=immich"
      "--label"
      "traefik.http.routers.immich-web.rule=Host(`immich.bspwr.com`)"
      "--label"
      "traefik.http.routers.immich-web.middlewares=default@file"
      "--label"
      "traefik.http.routers.immich-web.entrypoints=websecure"
      "--label"
      "traefik.http.routers.immich-web.tls=true"
      "--label"
      "traefik.http.routers.immich-web.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.immich-web.service=immich-web"
      "--label"
      "traefik.http.services.immich-web.loadbalancer.server.port=3000"
    ];
  };

  virtualisation.oci-containers.containers."immich-typesense" = {
    autoStart = true;
    image =
      "typesense/typesense:0.24.1@sha256:9bcff2b829f12074426ca044b56160ca9d777a0c488303469143dd9f8259d4dd";
    volumes = [ "/services/immich/typesense-data:/data" ];
    environment = {
      TYPESENSE_API_KEY = "Hm9TmG28tov8a5Xumt6j";
      TYPESENSE_DATA_DIR = "/data";
      # remove this to get debug messages
      GLOG_minloglevel = "1";
    };
    dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  virtualisation.oci-containers.containers."immich-redis" = {
    autoStart = true;
    image =
      "redis:6.2-alpine@sha256:3995fe6ea6a619313e31046bd3c8643f9e70f8f2b294ff82659d409b47d06abb";
    dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  virtualisation.oci-containers.containers."immich-postgres" = {
    autoStart = true;
    image =
      "postgres:14-alpine@sha256:874f566dd512d79cf74f59754833e869ae76ece96716d153b0fa3e64aec88d92";
    environmentFiles = [ "/services/immich/.env" ];
    environment = {
      POSTGRES_PASSWORD = "postgres";
      POSTGRES_USER = "postgres";
      POSTGRES_DB = "immich";
    };
    volumes = [ "/services/immich/postgres-data:/var/lib/postgresql/data" ];
    dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  # virtualisation.oci-containers.containers."immich-proxy" = {
  #   autoStart = true;
  #   image = "ghcr.io/immich-app/immich-proxy:release";
  #   dependsOn = [ "create-network-immich" "immich-server" "immich-web" ];
  #   extraOptions = [
  #     # networks
  #     "--network=immich"
  #     # labels
  #     "--label"
  #     "traefik.enable=true"
  #     "--label"
  #     "traefik.docker.network=immich"
  #     "--label"
  #     "traefik.http.routers.immich.rule=Host(`immich.bspwr.com`)"
  #     "--label"
  #     "traefik.http.routers.immich.entrypoints=websecure"
  #     "--label"
  #     "traefik.http.routers.immich.tls=true"
  #     "--label"
  #     "traefik.http.routers.immich.tls.certresolver=letsencrypt"
  #     "--label"
  #     "traefik.http.routers.immich.service=immich"
  #     "--label"
  #     "traefik.http.routers.immich.middlewares=default@file"
  #     "--label"
  #     "traefik.http.services.immich.loadbalancer.server.port=2283"
  #   ];
  # };

}
