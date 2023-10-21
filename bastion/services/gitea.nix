{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-gitea = {
    enable = true;
    description = "Create gitea docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-gitea" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create gitea || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."gitea" = {
    autoStart = true;
    image = "docker.io/gitea/gitea:latest";
    volumes =
      [ "/services/gitea/data:/data" "/etc/localtime:/etc/localtime:ro" ];
    environment = {
      USER_UID = "1000";
      USER_GID = "1000";
      GITEA__database__DB_TYPE = "postgres";
      GITEA__database__HOST = "gitea-postgres:5432";
      GITEA__database__NAME = "gitea";
      GITEA__database__USER = "gitea";
      GITEA__database__PASSWD = "gitea";
    };
    ports = [
      "2222:2222" # Gitea SSH
    ];
    dependsOn = [ "create-network-gitea" "gitea-postgres" ];
    extraOptions = [
      # networks
      "--network=gitea"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=gitea"
      "--label"
      "traefik.http.routers.gitea.rule=Host(`gitea.bspwr.com`, `gitea.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.gitea.entrypoints=websecure"
      "--label"
      "traefik.http.routers.gitea.tls=true"
      "--label"
      "traefik.http.routers.gitea.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.gitea.service=gitea"
      "--label"
      "traefik.http.routers.gitea.middlewares=default@file"
      "--label"
      "traefik.http.services.gitea.loadbalancer.server.port=3000"
    ];
  };

  virtualisation.oci-containers.containers."gitea-postgres" = {
    autoStart = true;
    image = "docker.io/postgres:14";
    volumes = [ "/services/gitea/postgres:/var/lib/postgresql/data" ];
    environment = {
      POSTGRES_USER = "gitea";
      POSTGRES_PASSWORD = "gitea";
      POSTGRES_DB = "gitea";
    };
    dependsOn = [ "create-network-gitea" ];
    extraOptions = [
      # networks
      "--network=gitea"
    ];
  };

}
