{ config, pkgs, lib, ... }: {

  # workaround for: newuidmap: write to uid_map failed: Operation not permitted
  # call podman ps with the correct newuidmap executable to set up rootless podman
  services.cron = {
    enable = true;
    systemCronJobs =
      [ "*/1 * * * * bree  PATH=/run/wrappers/bin:$PATH podman ps" ];
  };

  systemd.services.nginx-proxy-manager = {
    enable = true;
    description = "Nginx Proxy Manager";
    path = [ pkgs.podman-compose pkgs.podman pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.podman-compose}/bin/podman-compose up";
      ExecStop = "${pkgs.podman-compose}/bin/podman-compose down";
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
    path = [ pkgs.podman-compose pkgs.podman pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.podman-compose}/bin/podman-compose up";
      ExecStop = "${pkgs.podman-compose}/bin/podman-compose down";
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
    path = [ pkgs.podman-compose pkgs.podman pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.podman-compose}/bin/podman-compose up";
      ExecStop = "${pkgs.podman-compose}/bin/podman-compose down";
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
    path = [ pkgs.podman-compose pkgs.podman pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.podman-compose}/bin/podman-compose up";
      ExecStop = "${pkgs.podman-compose}/bin/podman-compose down";
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
    path = [ pkgs.podman-compose pkgs.podman pkgs.shadow ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.podman-compose}/bin/podman-compose up";
      ExecStop = "${pkgs.podman-compose}/bin/podman-compose down";
      WorkingDirectory = "/persist/services/projectsend";
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
  ];

}
