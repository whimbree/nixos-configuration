{ config, pkgs, lib, ... }: {
  systemd.services.docker-autoheal = {
    enable = true;
    description = "Monitor and restart unhealthy docker containers";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/docker-autoheal";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.nginx-proxy-manager = {
    enable = true;
    description = "Nginx Proxy Manager";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/nginx-proxy-manager";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.blog = {
    enable = true;
    description = "My blog";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/blog";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.minecraft-atm7 = {
    enable = false;
    description = "ATM7 Minecraft Server with RCON GUI";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/minecraft-atm7";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.minecraft-atm8 = {
    enable = true;
    description = "ATM8 Minecraft Server with RCON GUI";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/minecraft-atm8";
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
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/poste";
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
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/lxdware";
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
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/projectsend";
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
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/arr";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.portainer = {
    enable = true;
    description = "Portainer CE";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/portainer";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.heimdall = {
    enable = true;
    description = "Heimdall";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/heimdall";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.jellyfin = {
    enable = true;
    description = "Jellyfin";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/jellyfin";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.mullvad-sweden = {
    enable = true;
    description = "Mullvad Sweden Tunnel: Tailscale Exit Node & Browsers";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/mullvad-sweden";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

    systemd.services.mullvad-usa = {
    enable = true;
    description = "Mullvad USA Tunnel: Tailscale Exit Node";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/mullvad-usa";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.filebrowser = {
    enable = true;
    description = "File Browser WebUI";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/filebrowser";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.virt-manager = {
    enable = true;
    description = "Virt Manager";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/virt-manager";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.webdav = {
    enable = true;
    description = "WebDAV";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/webdav";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.nextcloud = {
    enable = true;
    description = "Nextcloud";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/nextcloud";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.i2p-tor-monerod = {
    enable = true;
    description = "I2P Proxy, Tor Proxy, Monero Node";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build --renew-anon-volumes";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build --renew-anon-volumes";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans --volumes";
      WorkingDirectory = "/etc/nixos/services/i2p-tor-monerod";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  # open TCP port 1080 1443 1081 for nginx-proxy-manager
  # open TCP port 4240->(4242) for Mullvad USA SOCKS Proxy
  # open TCP port 6960->(6969) for Mullvad Sweden SOCKS Proxy
  # open TCP port 7657 4443->(4444) for I2P HTTP Proxy
  # open TCP port 9049->(9050) for Tor SOCKS Proxy
  # open TCP port 1111 for blog
  # open TCP port 2443 9980 (Collabora) for Nextcloud
  # open TCP port 25565 for minecraft, 4326 4327 for RCON GUI
  # open TCP port 2025 2080 2110 2143 2465 2587 2993 2995 for poste.io
  # open TCP port 3080 for lxdware dashboard
  # open TCP port 4080 for ProjectSend
  # open TCP port 8112 for Deluge, 8989 for Sonarr, 7878 for Radarr
  # open TCP port 6767 for Bazarr, 8686 for Lidarr, 8787 for Readarr, 9696 for Prowlarr
  # open TCP port 5055 for Jellyseerr
  # open TCP port 8191 for FlareSolverr
  # open TCP port 9443 for Portainer
  # open TCP port 5080 for Heimdall
  # open TCP port 8096 8097 for Jellyfin
  # open TCP port 6600 6700 for Firefox Browser
  # open TCP port 6800 6900 for Tor Browser
  # open TCP port 6080 6090 for File Browser
  # open TCP port 8185 for Virt Manager
  # open TCP port 32080 for WebDAV
  # open TCP port 18080 18088->(18089) for Monero Node
  networking.firewall.allowedTCPPorts = [
    1080
    1443
    1081
    1111
    2443
    9980
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
    8112
    8989
    7878
    6767
    8686
    8787
    9696
    5055
    8191
    9443
    5080
    8096
    8097
    6600
    6700
    6800
    6900
    6080
    6090
    8185
    32080
    7657
    4443
    4444
    9049
    9050
    8080
    4240
    4242
    6960
    6969
    18080
    18088
    18089
  ];

  # open UDP port 51820 52000 53000 54000 for Wireguard
  # open UDP port 7359 1900 for Jellyfin
  networking.firewall.allowedUDPPorts = [ 51820 52000 53000 54000 7359 1900 ];
}