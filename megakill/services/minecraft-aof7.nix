{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-minecraft-aof7 = {
    enable = true;
    description = "Create minecraft-aof7 docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-minecraft-aof7" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create minecraft-aof7 || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-minecraft-aof7 = {
    after = lib.mkAfter [ "docker-create-network-minecraft-aof7.service" ];
    requires = lib.mkAfter [ "docker-create-network-minecraft-aof7.service" ];
  };
  virtualisation.oci-containers.containers."minecraft-aof7" = {
    autoStart = true;
    image = "docker.io/itzg/minecraft-server:java17";
    volumes = [ "/services/minecraft-aof7/data:/data" ];
    environment = {
      TZ = "America/New_York";
      EULA = "TRUE";
      VERSION = "1.20.1";
      TYPE = "FABRIC";
      FABRIC_LAUNCHER_VERSION = "0.10.2";
      FABRIC_LOADER_VERSION = "0.14.25";
      INIT_MEMORY = "4G";
      MAX_MEMORY = "12G";
      RCON_PASSWORD = "minecraft-aof7";
      USE_AIKAR_FLAGS = "true";
    };
    # dependsOn = [ "create-network-minecraft-aof7" ];
    ports = [ "0.0.0.0:25555:25565" ];
    extraOptions = [
      # hostname
      "--hostname=minecraft-aof7"
      # networks
      "--network=minecraft-aof7"
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

  systemd.services.docker-minecraft-aof7-rcon = {
    after = lib.mkAfter [ "docker-create-network-minecraft-aof7.service" ];
    requires = lib.mkAfter [ "docker-create-network-minecraft-aof7.service" ];
  };
  virtualisation.oci-containers.containers."minecraft-aof7-rcon" = {
    autoStart = true;
    image = "docker.io/itzg/rcon:latest";
    volumes = [ "/services/minecraft-aof7/rcon-web-db:/opt/rcon-web-admin/db" ];
    environment = {
      RWA_USERNAME = "admin";
      RWA_PASSWORD = "1337taco";
      RWA_ADMIN = "true";
      # is referring to the hostname of minecraft container
      RWA_RCON_HOST = "minecraft-aof7";
      # needs to match the password configured for the container, which is 'minecraft' by default
      RWA_RCON_PASSWORD = "minecraft-aof7";
      RWA_WEBSOCKET_URL_SSL =
        "wss://minecraft-aof7-rcon.local.bspwr.com/websocket";
      RWA_WEBSOCKET_URL = "ws://minecraft-aof7-rcon.local.bspwr.com/websocket";
    };
    # dependsOn = [ "create-network-minecraft-aof7" ];
    ports = [
      "0.0.0.0:4316:4326" # UI
      "0.0.0.0:4317:4327" # Websocket
    ];
    extraOptions = [
      # networks
      "--network=minecraft-aof7"
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

  systemd.services.docker-minecraft-aof7-filebrowser = {
    after = lib.mkAfter [ "docker-create-network-minecraft-aof7.service" ];
    requires = lib.mkAfter [ "docker-create-network-minecraft-aof7.service" ];
  };
  virtualisation.oci-containers.containers."minecraft-aof7-filebrowser" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:s6";
    volumes = [
      "/services/minecraft-aof7/data:/srv:ro"
      "/services/minecraft-aof7/filebrowser/database:/database"
      "/services/minecraft-aof7/filebrowser/config:/config"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
    };
    ports = [
      "0.0.0.0:25570:80" # UI
    ];
    # dependsOn = [ "create-network-minecraft-aof7" ];
    extraOptions = [
      # networks
      "--network=minecraft-aof7"
    ];
  };
}
