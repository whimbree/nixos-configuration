{ config, pkgs, lib, ... }: {

  # workaround for: newuidmap: write to uid_map failed: Operation not permitted
  # call podman ps with the correct newuidmap executable to set up rootless podman
  # services.cron = {
  #   enable = true;
  #   systemCronJobs =
  #     [ "*/1 * * * * bree  PATH=/run/wrappers/bin:$PATH podman ps" ];
  # };

  systemd.services.nginx-proxy-manager = {
    enable = true;
    description = "Nginx Proxy Manager";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      WorkingDirectory = "/persist/services/nginx-proxy-manager";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.atm7-mc-server = {
    enable = true;
    description = "ATM7 Minecraft Server with RCON GUI";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      WorkingDirectory = "/persist/services/atm7";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.poste-io = {
    enable = true;
    description = "Email Server with Web GUI";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      WorkingDirectory = "/persist/services/poste";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.lxdware-dashboard = {
    enable = true;
    description = "LXDWare Dashboard";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      WorkingDirectory = "/persist/services/lxdware";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.projectsend = {
    enable = true;
    description = "ProjectSend";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      WorkingDirectory = "/persist/services/projectsend";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.arr = {
    enable = true;
    description = "arr stack";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      WorkingDirectory = "/persist/services/arr";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # open TCP ports 1080 1443 1081 for nginx-proxy-manager
  # open TCP port 25565 for minecraft, 4326 4327 for RCON GUI
  # open TCP port 2025 2080 2110 2143 2465 2587 2993 2995 for poste.io
  # open TCP port 3080 for lxdware dashboard
  # open TCP port 4080 for ProjectSend
  # open TCP port 9091 for Transmission, 8989 for Sonarr, 7878 for Radarr
  # open TCP port 6767 for Bazarr, 8686 for Lidarr, 8787 for Readarr, 9696 for Prowlarr
  networking.firewall.allowedTCPPorts = [
    1080
    1443
    1081
    25565
    4326
    4327
    2025
    2080
    2110
    2143
    2465
    2587
    2993
    2995
    3080
    4080
    9091
    8989
    7878
    6767
    8686
    8787
    9696
  ];

  # open UDP port 51820 for Wireguard
  networking.firewall.allowedUDPPorts = [ 51820 ];

}
