{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-minecraft-vanillaplus = {
    enable = true;
    description = "Create minecraft-vanillaplus docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-minecraft-vanillaplus" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create minecraft-vanillaplus || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."minecraft-vanillaplus" = {
    autoStart = true;
    image = "docker.io/itzg/minecraft-server:java17";
    volumes = [ "/services/minecraft-vanillaplus/data:/data" ];
    environment = {
      TZ = "America/New_York";
      EULA = "TRUE";
      VERSION = "1.20.1";
      TYPE = "FABRIC";
      FABRIC_LAUNCHER_VERSION = "0.10.2";
      FABRIC_LOADER_VERSION = "0.14.25";
      INIT_MEMORY = "4G";
      MAX_MEMORY = "12G";
      RCON_PASSWORD = "minecraft-vanillaplus";
      USE_AIKAR_FLAGS = "true";
    };
    dependsOn = [ "create-network-minecraft-vanillaplus" ];
    ports = [ "0.0.0.0:25555:25565" ];
    extraOptions = [
      # hostname
      "--hostname=minecraft-vanillaplus"
      # networks
      "--network=minecraft-vanillaplus"
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

  virtualisation.oci-containers.containers."minecraft-vanillaplus-rcon" = {
    autoStart = true;
    image = "docker.io/itzg/rcon:latest";
    volumes = [ "/services/minecraft-vanillaplus/rcon-web-db:/opt/rcon-web-admin/db" ];
    environment = {
      RWA_USERNAME = "admin";
      RWA_PASSWORD = "1337taco";
      RWA_ADMIN = "true";
      # is referring to the hostname of minecraft container
      RWA_RCON_HOST = "minecraft-vanillaplus";
      # needs to match the password configured for the container, which is 'minecraft' by default
      RWA_RCON_PASSWORD = "minecraft-vanillaplus";
      RWA_WEBSOCKET_URL_SSL = "wss://minecraft-vanillaplus-rcon.whimsical.cloud/websocket";
      RWA_WEBSOCKET_URL = "ws://minecraft-vanillaplus-rcon.whimsical.cloud/websocket";
    };
    dependsOn = [ "create-network-minecraft-vanillaplus" ];
    ports = [
      "0.0.0.0:4316:4326" # UI
      "0.0.0.0:4317:4327" # Websocket
    ];
    extraOptions = [
      # networks
      "--network=minecraft-vanillaplus"
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

  virtualisation.oci-containers.containers."minecraft-vanillaplus-filebrowser" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:latest";
    volumes = [
      "/services/minecraft-vanillaplus/data:/srv:ro"
      "/services/minecraft-vanillaplus/filebrowser/database:/database"
      "/services/minecraft-vanillaplus/filebrowser/config:/config"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
    };
    ports = [
      "0.0.0.0:25570:80" # UI
    ];
    dependsOn = [ "create-network-minecraft-vanillaplus" ];
    extraOptions = [
      # networks
      "--network=minecraft-vanillaplus"
    ];
  };
}
