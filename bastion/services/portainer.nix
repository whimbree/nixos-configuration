{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-portainer = {
    enable = true;
    description = "Create portainer docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-portainer" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create portainer || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."portainer" = {
    autoStart = true;
    image = "docker.io/portainer/portainer-ce:2.19.4-alpine";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "/services/portainer/data:/data"
      "/etc/localtime:/etc/localtime:ro"
    ];
    dependsOn = [ "create-network-portainer" ];
    extraOptions = [
      # networks
      "--network=portainer"
      # healthcheck
      "--health-cmd"
      "wget --no-verbose --tries=1 --spider --no-check-certificate https://localhost:9443 || exit 1"
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
      "traefik.docker.network=portainer"
      "--label"
      "traefik.http.routers.portainer.rule=Host(`portainer.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.portainer.entrypoints=websecure"
      "--label"
      "traefik.http.routers.portainer.tls=true"
      "--label"
      "traefik.http.routers.portainer.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.portainer.tls.domains[0].main=*.local.bspwr.com"
      "--label"
      "traefik.http.routers.portainer.service=portainer"
      "--label"
      "traefik.http.routers.portainer.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.portainer.loadbalancer.server.port=9000"
    ];
  };
}
