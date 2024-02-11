{ config, pkgs, lib, ... }: {
  imports = [ ./services/minecraft-atm9.nix ./services/minecraft-vanillaplus.nix ./services/socks-proxy.nix ];

  # docker image auto update tool
  virtualisation.oci-containers.containers."watchtower" = {
    autoStart = true;
    image = "docker.io/containrrr/watchtower";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    environment = {
      TZ = "America/New_York";
      WATCHTOWER_CLEANUP = "true";
      WATCHTOWER_NO_RESTART = "true";
      # Run every day at 3:00 EDT
      WATCHTOWER_SCHEDULE = "0 0 3 * * *";
    };
  };

  # open TCP port 4326 4327 for RCON
  # open TCP port 25565 for Minecraft
  # open TCP port 25580 for Minecraft Fileshare
  networking.firewall.allowedTCPPorts = [ 4326 4327 25565 25580 ];

}
