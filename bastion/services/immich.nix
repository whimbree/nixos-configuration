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
    image = "ghcr.io/immich-app/immich-server:v1.91.3";
    cmd = [ "start.sh" "immich" ];
    volumes = [
      "/ocean/services/immich:/usr/src/app/upload"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [
      "create-network-immich"
      "immich-redis"
      "immich-postgres"
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
      "traefik.http.routers.immich.rule=Host(`immich.bspwr.com`)"
      "--label"
      "traefik.http.routers.immich.middlewares=default@file"
      "--label"
      "traefik.http.routers.immich.entrypoints=websecure"
      "--label"
      "traefik.http.routers.immich.tls=true"
      "--label"
      "traefik.http.routers.immich.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.immich.service=immich"
      "--label"
      "traefik.http.services.immich.loadbalancer.server.port=3001"
    ];
  };

  virtualisation.oci-containers.containers."immich-microservices" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-server:v1.91.3";
    cmd = [ "start.sh" "microservices" ];
    volumes = [
      "/ocean/services/immich:/usr/src/app/upload"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [
      "create-network-immich"
      "immich-redis"
      "immich-postgres"
    ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  virtualisation.oci-containers.containers."immich-machine-learning" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-machine-learning:v1.91.3";
    volumes = [ "/services/immich/model-cache:/cache" ];
    environmentFiles = [ "/services/immich/.env" ];
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
    image = "tensorchord/pgvecto-rs:pg14-v0.1.11";
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

}
