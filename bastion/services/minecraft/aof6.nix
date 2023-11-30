{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-minecraft-aof6 = {
    enable = true;
    description = "Create minecraft-aof6 docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-minecraft-aof6" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create minecraft-aof6 || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."minecraft-aof6" = {
    autoStart = true;
    image = "docker.io/itzg/minecraft-server:java17";
    volumes = [ "/services/minecraft-aof6/data:/data" ];
    environment = {
      EULA = "TRUE";
      VERSION = "1.19.2";
      TYPE = "FABRIC";
      INIT_MEMORY = "4G";
      MAX_MEMORY = "12G";
      RCON_PASSWORD = "minecraft-aof6";
    };
    dependsOn = [ "create-network-minecraft-aof6" ];
    ports = [ "0.0.0.0:25585:25565" ];
    extraOptions = [
      # hostname
      "--hostname=minecraft-aof6"
      # networks
      "--network=minecraft-aof6"
      # healthcheck
      "--health-cmd"
      "mc-health"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "1s"
      "--health-start-period"
      "10m"
    ];
  };

  virtualisation.oci-containers.containers."minecraft-aof6-rcon" = {
    autoStart = true;
    image = "docker.io/itzg/rcon:latest";
    volumes = [ "/services/minecraft-aof6/rcon-web-db:/opt/rcon-web-admin/db" ];
    environment = {
      RWA_USERNAME = "admin";
      RWA_PASSWORD = "1337taco";
      RWA_ADMIN = "true";
      # is referring to the hostname of minecraft container
      RWA_RCON_HOST = "minecraft-aof6";
      # needs to match the password configured for the container, which is 'minecraft' by default
      RWA_RCON_PASSWORD = "minecraft-aof6";
      RWA_WEBSOCKET_URL_SSL = "wss://minecraft-aof6-rcon.bspwr.com/websocket";
      RWA_WEBSOCKET_URL = "ws://minecraft-aof6-rcon.bspwr.com/websocket";
    };
    dependsOn = [ "create-network-minecraft-aof6" ];
    extraOptions = [
      # networks
      "--network=minecraft-aof6"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:4326 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "1s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=minecraft-aof6"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon.rule=Host(`minecraft-aof6-rcon.bspwr.com`)"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon.entrypoints=websecure"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon.tls=true"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon.service=minecraft-aof6-rcon"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.minecraft-aof6-rcon.loadbalancer.server.port=4326"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon-ws.rule=Host(`minecraft-aof6-rcon.bspwr.com`) && PathPrefix(`/websocket`)"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon-ws.entrypoints=websecure"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon-ws.tls=true"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon-ws.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon-ws.service=minecraft-aof6-rcon-ws"
      "--label"
      "traefik.http.routers.minecraft-aof6-rcon-ws.middlewares=minecraft-aof6-rcon-ws_strip, local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.minecraft-aof6-rcon-ws.loadbalancer.server.port=4327"
      "--label"
      "traefik.http.middlewares.minecraft-aof6-rcon-ws_strip.stripprefix.prefixes=/websocket"
    ];
  };
}
