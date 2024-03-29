{ config, pkgs, lib, ... }: {
  imports = [
    ./services/traefik.nix
    ./services/headscale.nix
    ./services/socks-proxy.nix
  ];

  # docker autoheal tool
  virtualisation.oci-containers.containers."dependheal" = {
    autoStart = true;
    image = "ghcr.io/whimbree/dependheal:latest";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    environment = { DEPENDHEAL_ENABLE_ALL = "true"; };
  };

  # docker image auto update tool
  virtualisation.oci-containers.containers."watchtower" = {
    autoStart = true;
    image = "docker.io/containrrr/watchtower";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    environment = {
      TZ = "America/New_York";
      WATCHTOWER_CLEANUP = "true";
      WATCHTOWER_NO_RESTART = "true";
      # Run every day at 1:00 EDT
      WATCHTOWER_SCHEDULE = "0 0 1 * * *";
    };
  };

  # open TCP port 80 443 for Traefik
  # open TCP port 25565 for Minecraft
  networking.firewall.allowedTCPPorts = [ 80 443 25565 ];
  # open UDP port 3478 for Headscale DERP
  networking.firewall.allowedUDPPorts = [ 3478 ];

}
