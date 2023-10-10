{ config, pkgs, lib, ... }: {
    imports = [
    ./services/arr.nix
    ./services/webdav.nix
    ./services/filebrowser.nix
    ./services/portainer.nix
    ./services/heimdall.nix
    ./services/jellyfin.nix
    ./services/headscale.nix
    ./services/poste.nix
    ./services/coturn.nix
    ./services/virt-manager.nix
    ./services/blog.nix
    ./services/mullvad-usa.nix
    ./services/mullvad-sweden.nix
    ./services/gitea.nix
    ./services/lxdware.nix
    ./services/projectsend.nix
    ./services/photoprism.nix
    ./services/nextcloud.nix
    ./services/incognito.nix
    ./services/piped.nix
    ./services/traefik.nix
    ./services/jitsi.nix
    ./services/matrix.nix
  ];

  systemd.services.docker-modprobe-wireguard = {
    enable = true;
    description = "modprobe wireguard";
    path = [ pkgs.kmod ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.kmod}/bin/modprobe wireguard";
      ExecStop = "${pkgs.kmod}/bin/modprobe -r wireguard";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

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
      # Run every day at 3:00 EDT
      WATCHTOWER_SCHEDULE = "0 0 3 * * *";
    };
  };

  # open TCP port 80 443 for Traefik
  # open TCP port 4242 for Mullvad USA SOCKS Proxy
  # open TCP port 6969 for Mullvad Sweden SOCKS Proxy
  # open TCP port 4444 for I2P HTTP Proxy
  # open TCP port 9050 for Tor SOCKS Proxy
  # open TCP port 18089 for Monero Node
  # open TCP port 25565 25585 for Minecraft
  # open TCP port 25 110 143 465 587 993 995 for poste.io
  # open TCP port 3478 for TURN Server
  # open TCP port 2222 for Gitea SSH
  # open TCP port 2200 for Endlessh SSH Tarpit
  networking.firewall.allowedTCPPorts = [
    80
    443
    4242
    6969
    4444
    9050
    18089
    25565
    25585
    25
    110
    143
    465
    587
    993
    995
    3478
    2222
    2200
  ];
  
  # open UDP port 3478 for TURN Server
  # open UDP port 10000 for Jitsi Meet
  networking.firewall.allowedUDPPorts = [
    3478
    10000
  ];
}