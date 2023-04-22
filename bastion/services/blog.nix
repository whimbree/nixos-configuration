{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-blog = {
    enable = true;
    description = "Create blog docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-blog" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create blog || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."blog" = {
    autoStart = true;
    image = "ghcr.io/bspwr/blog:latest";
    dependsOn = [ "create-network-blog" ];
    extraOptions = [
      # networks
      "--network=blog"
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
      "traefik.docker.network=blog"
      "--label"
      "traefik.http.routers.blog.rule=Host(`blog.bspwr.com`)"
      "--label"
      "traefik.http.routers.blog.entrypoints=websecure"
      "--label"
      "traefik.http.routers.blog.tls=true"
      "--label"
      "traefik.http.routers.blog.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.blog.service=blog"
      "--label"
      "traefik.http.routers.blog.middlewares=default@file"
      "--label"
      "traefik.http.services.blog.loadbalancer.server.port=80"
    ];
  };
}