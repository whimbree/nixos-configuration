{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-projectsend = {
    enable = true;
    description = "Create projectsend docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-projectsend" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create projectsend || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."projectsend" = {
    autoStart = true;
    image = "lscr.io/linuxserver/projectsend:latest";
    volumes = [
      "/services/projectsend/config:/config"
      "/ocean/services/projectsend:/data/projectsend"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
      MAX_UPLOAD = "1024000";
    };
    dependsOn = [ "create-network-projectsend" "projectsend-mariadb" ];
    extraOptions = [
      # networks
      "--network=projectsend"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:80 || exit 1"
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
      "traefik.docker.network=projectsend"
      "--label"
      "traefik.http.routers.projectsend.rule=Host(`projectsend.bspwr.com`)"
      "--label"
      "traefik.http.routers.projectsend.entrypoints=websecure"
      "--label"
      "traefik.http.routers.projectsend.tls=true"
      "--label"
      "traefik.http.routers.projectsend.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.projectsend.service=projectsend"
      "--label"
      "traefik.http.routers.projectsend.middlewares=default@file"
      "--label"
      "traefik.http.services.projectsend.loadbalancer.server.port=80"
    ];
  };

  virtualisation.oci-containers.containers."projectsend-mariadb" = {
    autoStart = true;
    image = "lscr.io/linuxserver/mariadb:latest";
    volumes = [ "/services/projectsend/mariadb:/config" ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
      MYSQL_ROOT_PASSWORD = "password";
      MYSQL_DATABASE = "projectsend";
      MYSQL_USER = "projectsend";
      MYSQL_PASSWORD = "projectsend";
    };
    dependsOn = [ "create-network-projectsend" ];
    extraOptions = [
      # networks
      "--network=projectsend"
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
}
