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

  systemd.services.docker-create-networks = {
    enable = true;
    description = "Create docker networks";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-networks" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create arr || true
        ${pkgs.docker}/bin/docker network create blog || true
        ${pkgs.docker}/bin/docker network create filebrowser || true
        ${pkgs.docker}/bin/docker network create headscale || true
        ${pkgs.docker}/bin/docker network create heimdall || true
        ${pkgs.docker}/bin/docker network create i2p-tor-monerod || true
        ${pkgs.docker}/bin/docker network create jellyfin || true
        ${pkgs.docker}/bin/docker network create lxdware || true
        ${pkgs.docker}/bin/docker network create minecraft-atm7 || true
        ${pkgs.docker}/bin/docker network create minecraft-atm8 || true
        ${pkgs.docker}/bin/docker network create mullvad-sweden || true
        ${pkgs.docker}/bin/docker network create mullvad-usa || true
        ${pkgs.docker}/bin/docker network create nextcloud || true
        ${pkgs.docker}/bin/docker network create nginx-proxy-manager || true
        ${pkgs.docker}/bin/docker network create portainer || true
        ${pkgs.docker}/bin/docker network create poste || true
        ${pkgs.docker}/bin/docker network create projectsend || true
        ${pkgs.docker}/bin/docker network create virt-manager || true
        ${pkgs.docker}/bin/docker network create webdav || true
      '';
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
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
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.headscale = {
    enable = true;
    description = "Headscale";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/headscale";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  # open TCP port 1080 1443 for nginx-proxy-manager
  # open TCP port (4242) for Mullvad USA SOCKS Proxy
  # open TCP port (6969) for Mullvad Sweden SOCKS Proxy
  # open TCP port (4444) for I2P HTTP Proxy
  # open TCP port (9050) for Tor SOCKS Proxy
  # open TCP port (18089) for Monero Node
  # open TCP port (25565) for minecraft
  # open TCP port 2025 2110 2143 2465 2587 2993 2995 for poste.io
  networking.firewall.allowedTCPPorts = [
    1080
    1443
    4242
    6969
    4444
    9050
    18089
    25565
    2025
    2110
    2143
    2465
    2587
    2993
    2995
  ];
}