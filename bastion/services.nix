{ config, pkgs, lib, ... }: {
  imports = [
    # ./services/airvpn-usa.nix
    # ./services/airvpn-sweden.nix
    # ./services/arr.nix
    # ./services/webdav.nix
    # ./services/filebrowser.nix
    # ./services/portainer.nix
    # ./services/heimdall.nix
    # ./services/heimdall-bspwr.nix
    # ./services/jellyfin.nix
    # ./services/headscale.nix
    # ./services/poste.nix
    # ./services/coturn.nix
    # ./services/virt-manager.nix
    # ./services/blog.nix
    # ./services/mullvad-usa.nix
    # ./services/mullvad-sweden.nix
    # ./services/gitea.nix # MUST BE SECURED WITH ANUBIS 
    # ./services/lxdware.nix
    # ./services/projectsend.nix BYE BYE! REST IN PISS
    # ./services/photoprism.nix
    # ./services/nextcloud.nix
    # ./services/incognito.nix
    # ./services/piped.nix # MUST BE SECURED WITH ANUBIS 
    # ./services/traefik.nix
    # ./services/jitsi.nix
    # ./services/matrix.nix
    # ./services/socks-proxy.nix
    # ./services/syncthing.nix
    # ./services/immich.nix
    # ./services/sftpgo.nix
  ];

virtualisation.oci-containers.containers."endlessh" = {
  autoStart = true;
  image = "docker.io/linuxserver/endlessh:latest";
  volumes = [ "/services/endlessh/config:/config" ];
  environment = { LOGFILE = "true"; };
  ports = [ "0.0.0.0:2200:2222" ];
  extraOptions = [
    # Drop all capabilities
    "--cap-drop=ALL"
    # No new privileges
    "--security-opt=no-new-privileges:true"
    # Disable privileged mode
    "--privileged=false"
    # Memory limits (prevent DoS)
    "--memory=128m"
    "--memory-swap=128m"
    # CPU limits
    "--cpus=0.5"
    # Process limits
    "--pids-limit=100"
  ];
};

  systemd.services.docker-modprobe-wireguard = {
    enable = true;
    description = "modprobe wireguard";
    path = [ pkgs.kmod ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart =
        "${pkgs.kmod}/bin/modprobe -a wireguard ip_tables iptable_filter ip6_tables ip6table_filter";
      ExecStop =
        "${pkgs.kmod}/bin/modprobe -ra wireguard ip_tables iptable_filter ip6_tables ip6table_filter";
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  # docker autoheal tool
  # virtualisation.oci-containers.containers."dependheal" = {
  #   autoStart = true;
  #   image = "ghcr.io/whimbree/dependheal:latest";
  #   volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
  #   environment = { DEPENDHEAL_ENABLE_ALL = "true"; };
  # };

  # docker image auto update tool
  # virtualisation.oci-containers.containers."watchtower" = {
  #   autoStart = true;
  #   image = "docker.io/containrrr/watchtower";
  #   volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
  #   environment = {
  #     TZ = "America/New_York";
  #     WATCHTOWER_CLEANUP = "true";
  #     WATCHTOWER_NO_RESTART = "true";
  #     # Run every day at 3:00 EDT
  #     WATCHTOWER_SCHEDULE = "0 0 3 * * *";
  #   };
  # };

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
  # open TCP port 18089 for Monero Node
  # open TCP port 25565 25585 for Minecraft
  # open TCP port 25 110 143 465 587 993 995 for poste.io
  # open TCP port 3478 for TURN Server
  # open TCP port 2222 for Gitea SSH
  # open TCP port 2200 for Endlessh SSH Tarpit
  networking.firewall.allowedTCPPorts = [ 80 443 2200 ];

  # open UDP port 3478 for TURN Server
  # open UDP port 10000 for Jitsi Meet
  # networking.firewall.allowedUDPPorts = [ 3478 10000 ];
}
