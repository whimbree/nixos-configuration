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
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-heimdall-bspwr = {
    after = lib.mkAfter [ "docker-create-network-heimdall.service" ];
    requires = lib.mkAfter [ "docker-create-network-heimdall.service" ];
  };
  virtualisation.oci-containers.containers."heimdall-bspwr" = {
    autoStart = true;
    image = "lscr.io/linuxserver/heimdall:latest";
    volumes = [ "/services/heimdall-bspwr/config:/config" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
    };
    # dependsOn = [ "create-network-heimdall" ];
    extraOptions = [
      # networks
      "--network=heimdall"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:80 || exit 1"
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
      "traefik.docker.network=heimdall"
      "--label"
      "traefik.http.routers.heimdall-bspwr.rule=Host(`bspwr.com`) || Host(`heimdall.bspwr.com`)"
      "--label"
      "traefik.http.routers.heimdall-bspwr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.heimdall-bspwr.tls=true"
      "--label"
      "traefik.http.routers.heimdall-bspwr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.heimdall-bspwr.tls.domains[0].main=bspwr.com"
      "--label"
      "traefik.http.routers.heimdall-bspwr.service=heimdall-bspwr"
      "--label"
      "traefik.http.routers.heimdall-bspwr.middlewares=default@file"
      "--label"
      "traefik.http.services.heimdall-bspwr.loadbalancer.server.port=80"
    ];
  };
}
