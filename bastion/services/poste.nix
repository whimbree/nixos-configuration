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
    wants = [ "network-online.target" ];
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
      "0.0.0.0:110:110" # Poste.io POP3 Server
      "0.0.0.0:995:995" # Poste.io POP3 Server
      "0.0.0.0:143:143" # Poste.io IMAP Server
      "0.0.0.0:993:993" # Poste.io IMAP Server
      "0.0.0.0:25:25"   # Poste.io SMTP Server
      "0.0.0.0:465:465" # Poste.io SMTP Server
      "0.0.0.0:587:587" # Poste.io SMTP Server
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
      "traefik.http.routers.poste.rule=Host(`mail.bspwr.com`)"
      "--label"
      "traefik.http.routers.poste.entrypoints=websecure"
      "--label"
      "traefik.http.routers.poste.tls=true"
      "--label"
      "traefik.http.routers.poste.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.poste.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.poste.service=poste"
      "--label"
      "traefik.http.routers.poste.middlewares=default@file"
      "--label"
      "traefik.http.services.poste.loadbalancer.server.port=80"
    ];
  };
}
