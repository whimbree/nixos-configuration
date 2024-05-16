{ config, pkgs, lib, ... }: {

  systemd.services.docker-create-network-jitsi = {
    enable = true;
    description = "Create jitsi docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-jitsi" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create meet.jitsi || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  # Frontend
  virtualisation.oci-containers.containers."jitsi-web" = {
    autoStart = true;
    image = "docker.io/jitsi/web:stable-8319";
    volumes = [
      "/services/jitsi/web:/config:Z"
      "/services/jitsi/web/crontabs:/var/spool/cron/crontabs:Z"
      "/services/jitsi/transcripts:/usr/share/jitsi-meet/transcripts:Z"
    ];
    environmentFiles = [ "/services/jitsi/.env" ];
    dependsOn = [ "create-network-jitsi" ];
    extraOptions = [
      # networks
      "--network=meet.jitsi"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=meet.jitsi"
      "--label"
      "traefik.http.routers.jitsi.rule=Host(`jitsi.bspwr.com`)"
      "--label"
      "traefik.http.routers.jitsi.entrypoints=websecure"
      "--label"
      "traefik.http.routers.jitsi.tls=true"
      "--label"
      "traefik.http.routers.jitsi.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.jitsi.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.jitsi.service=jitsi"
      "--label"
      "traefik.http.routers.jitsi.middlewares=default@file"
      "--label"
      "traefik.http.services.jitsi.loadbalancer.server.port=80"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  # XMPP server
  virtualisation.oci-containers.containers."jitsi-prosody" = {
    autoStart = true;
    image = "docker.io/jitsi/prosody:stable-8319";
    volumes = [
      "/services/jitsi/prosody/config:/config:Z"
      "/services/jitsi/prosody/prosody-plugins-custom:/prosody-plugins-custom:Z"
    ];
    environmentFiles = [ "/services/jitsi/.env" ];
    dependsOn = [ "create-network-jitsi" ];
    extraOptions = [
      # expose
      "--expose"
      "5222"
      "--expose"
      "5347"
      "--expose"
      "5280"
      # networks
      "--network=meet.jitsi"
      "--network-alias=xmpp.meet.jitsi"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  # Focus component
  virtualisation.oci-containers.containers."jitsi-jicofo" = {
    autoStart = true;
    image = "docker.io/jitsi/jicofo:stable-8319";
    volumes = [ "/services/jitsi/jicofo:/config:Z" ];
    environmentFiles = [ "/services/jitsi/.env" ];
    dependsOn = [ "create-network-jitsi" "jitsi-prosody" ];
    extraOptions = [
      # networks
      "--network=meet.jitsi"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  # Video bridge
  virtualisation.oci-containers.containers."jitsi-jvb" = {
    autoStart = true;
    image = "docker.io/jitsi/jvb:stable-8319";
    volumes = [ "/services/jitsi/jvb:/config:Z" ];
    ports = [ "0.0.0.0:10000:10000/udp" ];
    environmentFiles = [ "/services/jitsi/.env" ];
    dependsOn = [ "create-network-jitsi" "jitsi-prosody" ];
    extraOptions = [
      # networks
      "--network=meet.jitsi"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  # Provides services for recording or streaming
  virtualisation.oci-containers.containers."jitsi-jibri" = {
    autoStart = true;
    image = "docker.io/jitsi/jibri:stable-8319";
    volumes = [ "/services/jitsi/jibri:/config:Z" ];
    environment = { DISPLAY = ":0"; };
    environmentFiles = [ "/services/jitsi/.env" ];
    dependsOn = [ "create-network-jitsi" "jitsi-jicofo" ];
    extraOptions = [
      # networks
      "--network=meet.jitsi"
      # shm_size
      "--shm-size=2gb"
      # cap_add
      "--cap-add=SYS_ADMIN"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  # Etherpad: real-time collaborative document editing
  virtualisation.oci-containers.containers."etherpad" = {
    autoStart = true;
    image = "docker.io/etherpad/etherpad:1.8.6";
    volumes = [
      "/services/jitsi/web:/config:Z"
      "/services/jitsi/web/crontabs:/var/spool/cron/crontabs:Z"
      "/services/jitsi/transcripts:/usr/share/jitsi-meet/transcripts:Z"
    ];
    environment = {
      DB_TYPE = "postgres";
      DB_HOST = "etherpad-postgres";
      DB_PORT = "5432";
      DB_NAME = "etherpad";
      DB_USER = "etherpad";
      DB_PASS = "etherpad";
    };
    environmentFiles = [ "/services/jitsi/.env" ];
    dependsOn = [ "create-network-jitsi" "etherpad-postgres" ];
    extraOptions = [
      # networks
      "--network=meet.jitsi"
      "--network-alias=etherpad.meet.jitsi"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=meet.jitsi"
      "--label"
      "traefik.http.routers.etherpad.rule=Host(`etherpad.bspwr.com`)"
      "--label"
      "traefik.http.routers.etherpad.entrypoints=websecure"
      "--label"
      "traefik.http.routers.etherpad.tls=true"
      "--label"
      "traefik.http.routers.etherpad.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.etherpad.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.etherpad.service=etherpad"
      "--label"
      "traefik.http.routers.etherpad.middlewares=default@file"
      "--label"
      "traefik.http.services.etherpad.loadbalancer.server.port=9001"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."etherpad-postgres" = {
    autoStart = true;
    image = "docker.io/postgres:11";
    volumes = [ "/services/etherpad/postgresdata:/var/lib/postgresql/data" ];
    environment = {
      POSTGRES_DB = "etherpad";
      POSTGRES_USER = "etherpad";
      POSTGRES_PASSWORD = "etherpad";
      POSTGRES_INITDB_ARGS = "--lc-collate C --lc-ctype C --encoding UTF8";
    };
    dependsOn = [ "create-network-jitsi" ];
    extraOptions = [
      # networks
      "--network=meet.jitsi"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };
}
