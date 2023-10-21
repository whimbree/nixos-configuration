{ config, pkgs, lib, ... }: {
  imports = [ ./services/minecraft-atm9.nix ];

  # open TCP port 4326 4327 for RCON
  # open TCP port 25565 for Minecraft
  networking.firewall.allowedTCPPorts = [ 4326 4327 25565 ];

}
