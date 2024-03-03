{ config, pkgs, lib, ... }: {
  virtualisation.oci-containers.containers."traefik" = {
    autoStart = true;
    image = "docker.io/traefik:v2.10.5";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "/services/traefik/letsencrypt:/etc/traefik/letsencrypt"
      "/services/traefik/myresolver:/etc/traefik/myresolver"
      "/services/traefik/porkbun:/etc/traefik/porkbun"
      "/services/traefik/secrets:/etc/traefik/secrets"
      "/services/traefik/logs:/etc/traefik/logs"
      "/services/traefik/traefik.yml:/etc/traefik/traefik.yml"
      "/services/traefik/config.yml:/etc/traefik/config.yml"
    ];
    environment = {
      GOOGLE_DOMAINS_ACCESS_TOKEN_FILE =
        "/etc/traefik/secrets/google-domain-access-token";
      PORKBUN_API_KEY_FILE = "/etc/traefik/secrets/porkbun-api-key";
      PORKBUN_SECRET_API_KEY_FILE =
        "/etc/traefik/secrets/porkbun-secret-api-key";
    };
    # ports = [
    #   "0.0.0.0:80:80" # HTTP
    #   "0.0.0.0:443:443" # HTTPS
    #   "0.0.0.0:25565:25565" # Minecraft
    # ];
    extraOptions = [
      # networks
      "--network=host"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.http.routers.traefik.rule=Host(`traefik-wheatley.local.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.traefik.priority=1000"
      "--label"
      "traefik.http.routers.traefik.entrypoints=websecure"
      "--label"
      "traefik.http.routers.traefik.tls=true"
      "--label"
      "traefik.http.routers.traefik.tls.certresolver=myresolver"
      "--label"
      "traefik.http.routers.traefik.service=api@internal"
      "--label"
      "traefik.http.routers.traefik.middlewares=local-allowlist@file, default@file"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

}
