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
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-immich-server = {
    after = lib.mkAfter [ "docker-create-network-immich.service" ];
    requires = lib.mkAfter [ "docker-create-network-immich.service" ];
  };
  virtualisation.oci-containers.containers."immich-server" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-server:v1.133.0";
    volumes = [
      "/ocean/services/immich:/usr/src/app/upload"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environmentFiles = [ "/services/immich/.env" ];
    dependsOn = [
      # "create-network-immich" 
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
      "traefik.http.routers.immich.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.immich.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.immich.service=immich"
      "--label"
      "traefik.http.services.immich.loadbalancer.server.port=2283"
    ];
  };

  systemd.services.docker-immich-machine-learning = {
    after = lib.mkAfter [ "docker-create-network-immich.service" ];
    requires = lib.mkAfter [ "docker-create-network-immich.service" ];
  };
  virtualisation.oci-containers.containers."immich-machine-learning" = {
    autoStart = true;
    image = "ghcr.io/immich-app/immich-machine-learning:v1.133.0";
    volumes = [ "/services/immich/model-cache:/cache" ];
    environmentFiles = [ "/services/immich/.env" ];
    # dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  systemd.services.docker-immich-redis = {
    after = lib.mkAfter [ "docker-create-network-immich.service" ];
    requires = lib.mkAfter [ "docker-create-network-immich.service" ];
  };
  virtualisation.oci-containers.containers."immich-redis" = {
    autoStart = true;
    image =
      "docker.io/redis:6.2-alpine@sha256:148bb5411c184abd288d9aaed139c98123eeb8824c5d3fce03cf721db58066d8";
    # dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };

  systemd.services.docker-immich-postgres = {
    after = lib.mkAfter [ "docker-create-network-immich.service" ];
    requires = lib.mkAfter [ "docker-create-network-immich.service" ];
  };
  virtualisation.oci-containers.containers."immich-postgres" = {
    autoStart = true;
    image = "ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0";
    environmentFiles = [ "/services/immich/.env" ];
    environment = {
      POSTGRES_PASSWORD = "postgres";
      POSTGRES_USER = "postgres";
      POSTGRES_DB = "immich";
      POSTGRES_INITDB_ARGS = "--data-checksums";
    };
    volumes = [ "/services/immich/postgres-data:/var/lib/postgresql/data" ];
    # dependsOn = [ "create-network-immich" ];
    extraOptions = [
      # networks
      "--network=immich"
    ];
  };
}
