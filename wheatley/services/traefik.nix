{ config, pkgs, lib, ... }: {

  systemd.services.docker-create-network-traefik = {
    enable = true;
    description = "Create traefik docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-traefik" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create traefik || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."traefik" = {
    autoStart = true;
    image = "docker.io/traefik:v2.10.5";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "/services/traefik/letsencrypt:/etc/traefik/letsencrypt"
      "/services/traefik/myresolver:/etc/traefik/myresolver"
      "/services/traefik/secrets:/etc/traefik/secrets"
      "/services/traefik/logs:/etc/traefik/logs"
      "/services/traefik/traefik.yml:/etc/traefik/traefik.yml"
      "/services/traefik/config.yml:/etc/traefik/config.yml"
    ];
    environment = {
      GOOGLE_DOMAINS_ACCESS_TOKEN_FILE="/etc/traefik/secrets/google-domain-access-token";
    };
    ports = [
      "80:80" # HTTP
      "443:443" # HTTPS
    ];
    dependsOn = [ "create-network-traefik" ];
    extraOptions = [
      # networks
      "--network=traefik"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=traefik"
      "--label"
      "traefik.http.routers.traefik.rule=Host(`traefik-wheatley.local.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.traefik.priority=1000"
      "--label"
      "traefik.http.routers.traefik.entrypoints=websecure"
      "--label"
      "traefik.http.routers.traefik.tls=true"
      "--label"
      "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.traefik.service=api@internal"
      "--label"
      "traefik.http.routers.traefik.middlewares=local-allowlist@file, default@file"
      ## dependheal
      "--label"
      "dependheal.enable=true"
      ### additional networks
      "--label"
      "dependheal.networks=headscale"
    ];
  };

}
