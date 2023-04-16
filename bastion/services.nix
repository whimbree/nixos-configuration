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
        ${pkgs.docker}/bin/docker network create gitea || true
        ${pkgs.docker}/bin/docker network create headscale || true
        ${pkgs.docker}/bin/docker network create heimdall || true
        ${pkgs.docker}/bin/docker network create incognito || true
        ${pkgs.docker}/bin/docker network create jellyfin || true
        ${pkgs.docker}/bin/docker network create jenkins || true
        ${pkgs.docker}/bin/docker network create lxdware || true
        ${pkgs.docker}/bin/docker network create matrix || true
        ${pkgs.docker}/bin/docker network create meet.jitsi || true
        ${pkgs.docker}/bin/docker network create minecraft-atm7 || true
        ${pkgs.docker}/bin/docker network create minecraft-atm8 || true
        ${pkgs.docker}/bin/docker network create minecraft-enigmatica2 || true
        ${pkgs.docker}/bin/docker network create mullvad-sweden || true
        ${pkgs.docker}/bin/docker network create mullvad-usa || true
        ${pkgs.docker}/bin/docker network create nextcloud || true
        ${pkgs.docker}/bin/docker network create photoprism || true
        ${pkgs.docker}/bin/docker network create portainer || true
        ${pkgs.docker}/bin/docker network create poste || true
        ${pkgs.docker}/bin/docker network create projectsend || true
        ${pkgs.docker}/bin/docker network create traefik || true 
        ${pkgs.docker}/bin/docker network create virt-manager || true
        ${pkgs.docker}/bin/docker network create webdav || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.traefik = {
    enable = true;
    description = "Traefik Proxy";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/traefik";
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
    enable = false;
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

  systemd.services.minecraft-enigmatica2 = {
    enable = true;
    description = "Enigmatica 2 Minecraft Server with RCON GUI";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/minecraft-enigmatica2";
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
    description = "Mullvad Sweden Tunnel: Tailscale Exit Node & SOCKS5 Proxy";
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
    description = "Mullvad USA Tunnel: Tailscale Exit Node & SOCKS5 Proxy";
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

  systemd.services.incognito = {
    enable = true;
    description = "Privacy (Incognito) Services";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build --renew-anon-volumes";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build --renew-anon-volumes";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans --volumes";
      WorkingDirectory = "/etc/nixos/services/incognito";
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

  systemd.services.gitea = {
    enable = true;
    description = "Gitea";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/gitea";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.jenkins = {
    enable = false;
    description = "Jenkins";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/jenkins";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.photoprism = {
    enable = true;
    description = "PhotoPrism";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/photoprism";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.matrix = {
    enable = true;
    description = "Matrix & Element";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/matrix";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.jitsi = {
    enable = true;
    description = "Jitsi Meet";
    path = [ pkgs.docker-compose pkgs.docker pkgs.shadow ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecReloadPre = "${pkgs.docker-compose}/bin/docker-compose pull --quiet --parallel";
      ExecReload = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans --build";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down --remove-orphans";
      WorkingDirectory = "/etc/nixos/services/jitsi";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "bree";
    };
    after = [ "network-online.target" "docker-create-networks.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."dependheal" = {
    autoStart = true;
    image = "dependheal:latest";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
    ];
    extraOptions = [
      "--name=dependheal"
    ];
  };

  # open TCP port 80 443 for Traefik
  # open TCP port 4242 for Mullvad USA SOCKS Proxy
  # open TCP port 6969 for Mullvad Sweden SOCKS Proxy
  # open TCP port 4444 for I2P HTTP Proxy
  # open TCP port 9050 for Tor SOCKS Proxy
  # open TCP port 18089 for Monero Node
  # open TCP port 25565 for Minecraft
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