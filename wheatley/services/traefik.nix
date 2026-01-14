{ config, pkgs, lib, ... }: {
  virtualisation.oci-containers.containers."traefik" = {
    autoStart = true;
    image = "docker.io/traefik:v3";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "/services/traefik/letsencrypt:/etc/traefik/letsencrypt"
      "/services/traefik/myresolver:/etc/traefik/myresolver"
      "/services/traefik/porkbun:/etc/traefik/porkbun"
      "/services/traefik/secrets:/etc/traefik/secrets"
      "/services/traefik/traefik.yml:/etc/traefik/traefik.yml"
      "/services/traefik/config.yml:/etc/traefik/config.yml"
      "/var/log/traefik:/etc/traefik/logs"
    ];
    environment = {
      GOOGLE_DOMAINS_ACCESS_TOKEN_FILE =
        "/etc/traefik/secrets/google-domain-access-token";
      PORKBUN_API_KEY_FILE = "/etc/traefik/secrets/porkbun-api-key";
      PORKBUN_SECRET_API_KEY_FILE =
        "/etc/traefik/secrets/porkbun-secret-api-key";
    };
    extraOptions = [
      # networks
      "--network=host"
    ];
  };

}
