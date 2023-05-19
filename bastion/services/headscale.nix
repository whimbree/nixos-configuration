{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-headscale = {
    enable = true;
    description = "Create headscale docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-headscale" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create headscale || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."headscale" = {
    autoStart = true;
    image = "docker.io/headscale/headscale:0.22.1";
    volumes = [
      "/services/headscale/config:/etc/headscale"
      "/services/headscale/data:/var/lib/headscale"
    ];
    dependsOn = [ "create-network-headscale" ];
    cmd = [ "headscale" "serve" ];
    extraOptions = [
      # networks
      "--network=headscale"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=headscale"
      "--label"
      "traefik.http.routers.headscale.rule=Host(`headscale.bspwr.com`) && PathPrefix(`/`)"
      "--label"
      "traefik.http.routers.headscale.entrypoints=websecure"
      "--label"
      "traefik.http.routers.headscale.tls=true"
      "--label"
      "traefik.http.routers.headscale.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.headscale.service=headscale"
      "--label"
      "traefik.http.routers.headscale.middlewares=default@file"
      "--label"
      "traefik.http.services.headscale.loadbalancer.server.port=8080"
    ];
  };

  virtualisation.oci-containers.containers."headscale-ui" = {
    autoStart = true;
    image = "ghcr.io/gurucomputing/headscale-ui:latest";
    dependsOn = [ "create-network-headscale" ];
    extraOptions = [
      # networks
      "--network=headscale"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 --no-check-certificate https://localhost:443 || exit 1"
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
      "traefik.docker.network=headscale"
      "--label"
      "traefik.http.routers.headscale-ui.rule=Host(`headscale.bspwr.com`) && PathPrefix(`/web`)"
      "--label"
      "traefik.http.routers.headscale-ui.entrypoints=websecure"
      "--label"
      "traefik.http.routers.headscale-ui.tls=true"
      "--label"
      "traefik.http.routers.headscale-ui.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.headscale-ui.service=headscale-ui"
      "--label"
      "traefik.http.routers.headscale-ui.middlewares=default@file"
      "--label"
      "traefik.http.services.headscale-ui.loadbalancer.server.port=80"
    ];
  };

}
