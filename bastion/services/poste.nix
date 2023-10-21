{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-poste = {
    enable = true;
    description = "Create poste docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-poste" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create poste || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."poste-io" = {
    autoStart = true;
    image = "docker.io/analogic/poste.io:latest";
    volumes = [ "/services/poste/data:/data" ];
    environment = {
      TZ = "America/New_York";
      HTTPS = "OFF";
    };
    ports = [
      "110:110" # Poste.io POP3 Server
      "995:995" # Poste.io POP3 Server
      "143:143" # Poste.io IMAP Server
      "993:993" # Poste.io IMAP Server
      "25:25"   # Poste.io SMTP Server
      "465:465" # Poste.io SMTP Server
      "587:587" # Poste.io SMTP Server
    ];
    dependsOn = [ "create-network-poste" ];
    extraOptions = [
      # networks
      "--network=poste"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=poste"
      "--label"
      "traefik.http.routers.poste.rule=Host(`mail.bspwr.com`, `mail.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.poste.entrypoints=websecure"
      "--label"
      "traefik.http.routers.poste.tls=true"
      "--label"
      "traefik.http.routers.poste.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.poste.service=poste"
      "--label"
      "traefik.http.routers.poste.middlewares=default@file"
      "--label"
      "traefik.http.services.poste.loadbalancer.server.port=80"
    ];
  };
}
