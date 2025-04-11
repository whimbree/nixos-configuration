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
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."headscale" = {
    autoStart = true;
    image = "docker.io/headscale/headscale:0.22";
    volumes = [
      "/services/headscale/config:/etc/headscale"
      "/services/headscale/data:/var/lib/headscale"
    ];
    ports = [ "0.0.0.0:3478:3478" ];
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
      "traefik.http.routers.headscale.rule=Host(`headscale.whimsical.cloud`) && PathPrefix(`/`)"
      "--label"
      "traefik.http.routers.headscale.priority=1000"
      "--label"
      "traefik.http.routers.headscale.entrypoints=websecure"
      "--label"
      "traefik.http.routers.headscale.tls=true"
      "--label"
      "traefik.http.routers.headscale.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.headscale.service=headscale"
      "--label"
      "traefik.http.routers.headscale.middlewares=default@file,headscale-cors@file"
      "--label"
      "traefik.http.services.headscale.loadbalancer.server.port=8080"
    ];
  };
  

  virtualisation.oci-containers.containers."headplane" = {
    autoStart = true;
    image = "ghcr.io/tale/headplane:0.5.10";
    dependsOn = [ "create-network-headscale" ];
    volumes = [
      "/services/headplane/config.yaml:/etc/headplane/config.yaml"
      # This should match headscale.config_path in your config.yaml
      "/services/headscale/config/config.yaml:/etc/headscale/config.yaml"
      # Headplane stores its data in this directory
      "/services/headplane/data:/var/lib/headplane"
      # Mount docker socket to use docker integration
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    extraOptions = [
      # networks
      "--network=headscale"
      # healthcheck
      # "--health-cmd"
      # "wget -qO- --no-verbose --tries=1 --no-check-certificate https://localhost:3000 || exit 1"
      # "--health-interval"
      # "10s"
      # "--health-retries"
      # "6"
      # "--health-timeout"
      # "2s"
      # "--health-start-period"
      # "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=headscale"
      "--label"
      "traefik.http.routers.headplane.rule=Host(`headscale.whimsical.cloud`) && PathPrefix(`/admin`)"
      "--label"
      "traefik.http.routers.headplane.priority=1001"
      "--label"
      "traefik.http.routers.headplane.entrypoints=websecure"
      "--label"
      "traefik.http.routers.headplane.tls=true"
      "--label"
      "traefik.http.routers.headplane.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.headplane.service=headplane"
      "--label"
      "traefik.http.routers.headplane.middlewares=default@file"
      "--label"
      "traefik.http.services.headplane.loadbalancer.server.port=3000"
    ];
  };

}
