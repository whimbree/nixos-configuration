{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-minecraft-atm9 = {
    enable = true;
    description = "Create minecraft-atm9 docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-minecraft-atm9" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create minecraft-atm9 || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-minecraft-atm9 = {
    after = lib.mkAfter [ "docker-create-network-minecraft-atm9.service" ];
    wants = lib.mkAfter [ "docker-create-network-minecraft-atm9.service" ];
  };
  virtualisation.oci-containers.containers."minecraft-atm9" = {
    autoStart = true;
    image = "docker.io/itzg/minecraft-server:java17";
    volumes = [ "/services/minecraft-atm9/data:/data" ];
    environment = {
      TZ = "America/New_York";
      EULA = "TRUE";
      VERSION = "1.20.1";
      TYPE = "FORGE";
      FORGEVERSION = "47.2.16";
      INIT_MEMORY = "4G";
      MAX_MEMORY = "12G";
      RCON_PASSWORD = "minecraft-atm9";
      USE_AIKAR_FLAGS = "true";
    };
    # dependsOn = [ "create-network-minecraft-atm9" ];
    ports = [ "0.0.0.0:25565:25565" ];
    extraOptions = [
      # hostname
      "--hostname=minecraft-atm9"
      # networks
      "--network=minecraft-atm9"
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
      "20m"
    ];
  };

  systemd.services.docker-minecraft-atm9-rcon = {
    after = lib.mkAfter [ "docker-create-network-minecraft-atm9.service" ];
    wants = lib.mkAfter [ "docker-create-network-minecraft-atm9.service" ];
  };
  virtualisation.oci-containers.containers."minecraft-atm9-rcon" = {
    autoStart = true;
    image = "docker.io/itzg/rcon:latest";
    volumes = [ "/services/minecraft-atm9/rcon-web-db:/opt/rcon-web-admin/db" ];
    environment = {
      RWA_USERNAME = "admin";
      RWA_PASSWORD = "1337taco";
      RWA_ADMIN = "true";
      # is referring to the hostname of minecraft container
      RWA_RCON_HOST = "minecraft-atm9";
      # needs to match the password configured for the container, which is 'minecraft' by default
      RWA_RCON_PASSWORD = "minecraft-atm9";
      RWA_WEBSOCKET_URL_SSL = "wss://minecraft-rcon.local.bspwr.com/websocket";
      RWA_WEBSOCKET_URL = "ws://minecraft-rcon.local.bspwr.com/websocket";
    };
    # dependsOn = [ "create-network-minecraft-atm9" ];
    ports = [
      "0.0.0.0:4326:4326" # UI
      "0.0.0.0:4327:4327" # Websocket
    ];
    extraOptions = [
      # networks
      "--network=minecraft-atm9"
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
    ];
  };

  systemd.services.docker-minecraft-atm9-filebrowser = {
    after = lib.mkAfter [ "docker-create-network-minecraft-atm9.service" ];
    wants = lib.mkAfter [ "docker-create-network-minecraft-atm9.service" ];
  };
  virtualisation.oci-containers.containers."minecraft-atm9-filebrowser" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:s6";
    volumes = [
      "/services/minecraft-atm9/data:/srv:ro"
      "/services/minecraft-atm9/filebrowser/database:/database"
      "/services/minecraft-atm9/filebrowser/config:/config"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
    };
    ports = [
      "0.0.0.0:25580:80" # UI
    ];
    # dependsOn = [ "create-network-minecraft-atm9" ];
    extraOptions = [
      # networks
      "--network=minecraft-atm9"
    ];
  };
}
