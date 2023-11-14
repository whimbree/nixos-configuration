{ config, pkgs, lib, ... }: {
  imports = [ ./services/minecraft-atm9.nix ./services/socks-proxy.nix ];

  # open TCP port 4326 4327 for RCON
  # open TCP port 25565 for Minecraft
  # open TCP port 25580 for Minecraft Fileshare
  # open TCP port 1080 for SOCKS Proxy
  networking.firewall.allowedTCPPorts = [ 4326 4327 25565 25580 1080 ];

}
