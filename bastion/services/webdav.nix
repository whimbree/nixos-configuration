{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-webdav = {
    enable = true;
    description = "Create webdav docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-webdav" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create webdav || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."webdav-alex-duplicati" = {
    autoStart = true;
    image = "docker.io/dgraziotin/nginx-webdav-nononsense:latest";
    volumes = [
      "/ocean/backup/duplicati/alex:/data"
      "/services/webdav/alex-duplicati-config:/config"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
      SERVER_NAMES = "localhost";
      TIMEOUTS_S = "3600"; # these are seconds
      CLIENT_MAX_BODY_SIZE = "10G"; # must end with M(egabytes) or G(igabytes)
    };
    dependsOn = [ "create-network-webdav" ];
    extraOptions = [
      # networks
      "--network=webdav"
      # healthcheck
      "--health-cmd"
      "curl localhost:80 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=webdav"
      "--label"
      "traefik.http.routers.alex-duplicati.rule=Host(`alex-duplicati.bspwr.com`)"
      "--label"
      "traefik.http.routers.alex-duplicati.entrypoints=websecure"
      "--label"
      "traefik.http.routers.alex-duplicati.tls=true"
      "--label"
      "traefik.http.routers.alex-duplicati.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.alex-duplicati.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.alex-duplicati.service=alex-duplicati"
      "--label"
      "traefik.http.routers.alex-duplicati.middlewares=default@file"
      "--label"
      "traefik.http.services.alex-duplicati.loadbalancer.server.port=80"
    ];
  };
}
