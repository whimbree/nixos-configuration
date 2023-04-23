{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-minecraft-vanilla = {
    enable = true;
    description = "Create minecraft-vanilla docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-minecraft-vanilla" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create minecraft-vanilla || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."minecraft-vanilla" = {
    autoStart = true;
    image = "docker.io/itzg/minecraft-server:java17";
    volumes = [ "/services/minecraft-vanilla/data:/data" ];
    environment = {
      EULA = "TRUE";
      VERSION = "1.19.4";
      TYPE = "PURPUR";
      INIT_MEMORY = "4G";
      MAX_MEMORY = "12G";
      RCON_PASSWORD = "minecraft-vanilla";
    };
    dependsOn = [ "create-network-minecraft-vanilla" ];
    ports = [ "25565:25565" ];
    extraOptions = [
      # hostname
      "--hostname=minecraft-vanilla"
      # networks
      "--network=minecraft-vanilla"
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

  virtualisation.oci-containers.containers."minecraft-vanilla-rcon" = {
    autoStart = true;
    image = "docker.io/itzg/rcon:latest";
    volumes =
      [ "/services/minecraft-vanilla/rcon-web-db:/opt/rcon-web-admin/db" ];
    environment = {
      RWA_USERNAME = "admin";
      RWA_PASSWORD = "1337taco";
      RWA_ADMIN = "true";
      # is referring to the hostname of minecraft container
      RWA_RCON_HOST = "minecraft-vanilla";
      # needs to match the password configured for the container, which is 'minecraft' by default
      RWA_RCON_PASSWORD = "minecraft-vanilla";
      RWA_WEBSOCKET_URL_SSL =
        "wss://minecraft-vanilla-rcon.bspwr.com/websocket";
      RWA_WEBSOCKET_URL = "ws://minecraft-vanilla-rcon.bspwr.com/websocket";
    };
    dependsOn = [ "create-network-minecraft-vanilla" ];
    extraOptions = [
      # networks
      "--network=minecraft-vanilla"
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
      "traefik.docker.network=minecraft-vanilla"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon.rule=Host(`minecraft-vanilla-rcon.bspwr.com`)"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon.entrypoints=websecure"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon.tls=true"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon.service=minecraft-vanilla-rcon"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.minecraft-vanilla-rcon.loadbalancer.server.port=4326"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon-ws.rule=Host(`minecraft-vanilla-rcon.bspwr.com`) && PathPrefix(`/websocket`)"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon-ws.entrypoints=websecure"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon-ws.tls=true"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon-ws.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon-ws.service=minecraft-vanilla-rcon-ws"
      "--label"
      "traefik.http.routers.minecraft-vanilla-rcon-ws.middlewares=minecraft-vanilla-rcon-ws_strip, local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.minecraft-vanilla-rcon-ws.loadbalancer.server.port=4327"
      "--label"
      "traefik.http.middlewares.minecraft-vanilla-rcon-ws_strip.stripprefix.prefixes=/websocket"
    ];
  };
}
