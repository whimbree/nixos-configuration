{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-minecraft-atm8 = {
    enable = true;
    description = "Create minecraft-atm8 docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-minecraft-atm8" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create minecraft-atm8 || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."minecraft-atm8" = {
    autoStart = true;
    image = "docker.io/itzg/minecraft-server:java17";
    volumes = [ "/services/minecraft-atm8/data:/data" ];
    environment = {
      EULA = "TRUE";
      VERSION = "1.19.2";
      TYPE = "FORGE";
      FORGEVERSION = "43.1.55";
      INIT_MEMORY = "4G";
      MAX_MEMORY = "12G";
      RCON_PASSWORD = "minecraft-atm8";
    };
    dependsOn = [ "create-network-minecraft-atm8" ];
    ports = [ "25565:25565" ];
    extraOptions = [
      # hostname
      "--hostname=minecraft-atm8"
      # networks
      "--network=minecraft-atm8"
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

  virtualisation.oci-containers.containers."minecraft-atm8-rcon" = {
    autoStart = true;
    image = "docker.io/itzg/rcon:latest";
    volumes = [ "/services/minecraft-atm8/rcon-web-db:/opt/rcon-web-admin/db" ];
    environment = {
      RWA_USERNAME = "admin";
      RWA_PASSWORD = "1337taco";
      RWA_ADMIN = "true";
      # is referring to the hostname of minecraft container
      RWA_RCON_HOST = "minecraft-atm8";
      # needs to match the password configured for the container, which is 'minecraft' by default
      RWA_RCON_PASSWORD = "minecraft-atm8";
      RWA_WEBSOCKET_URL_SSL = "wss://minecraft-rcon.bspwr.com/websocket";
      RWA_WEBSOCKET_URL = "ws://minecraft-rcon.bspwr.com/websocket";
    };
    dependsOn = [ "create-network-minecraft-atm8" ];
    extraOptions = [
      # networks
      "--network=minecraft-atm8"
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
      "traefik.docker.network=minecraft-atm8"
      "--label"
      "traefik.http.routers.minecraft-rcon.rule=Host(`minecraft-rcon.bspwr.com`)"
      "--label"
      "traefik.http.routers.minecraft-rcon.entrypoints=websecure"
      "--label"
      "traefik.http.routers.minecraft-rcon.tls=true"
      "--label"
      "traefik.http.routers.minecraft-rcon.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.minecraft-rcon.service=minecraft-rcon"
      "--label"
      "traefik.http.routers.minecraft-rcon.middlewares=default@file"
      "--label"
      "traefik.http.services.minecraft-rcon.loadbalancer.server.port=4326"
      "--label"
      "traefik.http.routers.minecraft-rcon-ws.rule=Host(`minecraft-rcon.bspwr.com`) && PathPrefix(`/websocket`)"
      "--label"
      "traefik.http.routers.minecraft-rcon-ws.entrypoints=websecure"
      "--label"
      "traefik.http.routers.minecraft-rcon-ws.tls=true"
      "--label"
      "traefik.http.routers.minecraft-rcon-ws.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.minecraft-rcon-ws.service=minecraft-rcon-ws"
      "--label"
      "traefik.http.routers.minecraft-rcon-ws.middlewares=minecraft-rcon-ws_strip, default@file"
      "--label"
      "traefik.http.services.minecraft-rcon-ws.loadbalancer.server.port=4327"
      "--label"
      "traefik.http.middlewares.minecraft-rcon-ws_strip.stripprefix.prefixes=/websocket"
    ];
  };
}
