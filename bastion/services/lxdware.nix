{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-lxdware = {
    enable = true;
    description = "Create lxdware docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-lxdware" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create lxdware || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."lxdware" = {
    autoStart = true;
    image = "docker.io/lxdware/dashboard:latest";
    volumes = [ "/services/lxdware/lxdware:/var/lxdware" ];
    dependsOn = [ "create-network-lxdware" ];
    extraOptions = [
      # networks
      "--network=lxdware"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=lxdware"
      "--label"
      "traefik.http.routers.lxdware.rule=Host(`lxd.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.lxdware.entrypoints=websecure"
      "--label"
      "traefik.http.routers.lxdware.tls=true"
      "--label"
      "traefik.http.routers.lxdware.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.lxdware.tls.domains[0].main=*.local.bspwr.com"
      "--label"
      "traefik.http.routers.lxdware.service=lxdware"
      "--label"
      "traefik.http.routers.lxdware.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.lxdware.loadbalancer.server.port=80"
    ];
  };
}
