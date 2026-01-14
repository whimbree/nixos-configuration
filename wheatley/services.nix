{ config, pkgs, lib, ... }: {
  imports = [
    ./services/traefik.nix
    ./services/headscale.nix
    # ./services/socks-proxy.nix
  ];

  # docker image auto update tool
  virtualisation.oci-containers.containers."watchtower" = {
    autoStart = true;
    image = "docker.io/containrrr/watchtower";
    volumes = [ "/var/run/podman/podman.sock:/var/run/docker.sock" ];
    environment = {
      TZ = "America/New_York";
      WATCHTOWER_CLEANUP = "true";
      WATCHTOWER_NO_RESTART = "true";
      # Run every day at 1:00 EDT
      WATCHTOWER_SCHEDULE = "0 0 1 * * *";
    };
  };

  systemd.services.sockd = {
    description = "microsocks SOCKS5 proxy";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.microsocks}/bin/microsocks -i 0.0.0.0 -p 1080";
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 1080 ];

  # open TCP port 80 443 for Traefik
  networking.firewall.allowedTCPPorts = [ 80 443 ];
  # open UDP port 3478 for Headscale DERP
  networking.firewall.allowedUDPPorts = [ 3478 ];

}
