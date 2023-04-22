{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-heimdall = {
    enable = true;
    description = "Create heimdall docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-heimdall" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create heimdall || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."heimdall" = {
    autoStart = true;
    image = "lscr.io/linuxserver/heimdall:latest";
    volumes = [
      "/services/heimdall/config:/config"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
    };
    extraOptions = [
      # networks
      "--network=heimdall"
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
      "traefik.docker.network=heimdall"
      "--label"
      "traefik.http.routers.heimdall.rule=Host(`bspwr.com`, `heimdall.bspwr.com`)"
      "--label"
      "traefik.http.routers.heimdall.entrypoints=websecure"
      "--label"
      "traefik.http.routers.heimdall.tls=true"
      "--label"
      "traefik.http.routers.heimdall.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.heimdall.service=heimdall"
      "--label"
      "traefik.http.routers.heimdall.middlewares=default@file"
      "--label"
      "traefik.http.services.heimdall.loadbalancer.server.port=80"
    ];
  };
}