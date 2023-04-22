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

  systemd.services.docker-create-networks = {
    enable = true;
    description = "Create docker networks";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-networks" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create incognito || true
        ${pkgs.docker}/bin/docker network create jenkins || true
        ${pkgs.docker}/bin/docker network create matrix || true
        ${pkgs.docker}/bin/docker network create meet.jitsi || true
        ${pkgs.docker}/bin/docker network create minecraft-atm7 || true
        ${pkgs.docker}/bin/docker network create minecraft-atm8 || true
        ${pkgs.docker}/bin/docker network create minecraft-enigmatica2 || true
        ${pkgs.docker}/bin/docker network create nextcloud || true
        ${pkgs.docker}/bin/docker network create photoprism || true
        ${pkgs.docker}/bin/docker network create projectsend || true
        ${pkgs.docker}/bin/docker network create traefik || true 
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

  # docker autoheal tool
  virtualisation.oci-containers.containers."dependheal" = {
    autoStart = true;
    image = "ghcr.io/bspwr/dependheal:latest";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    environment = { DEPENDHEAL_ENABLE_ALL = "true"; };
  };

  # docker job scheduler
  virtualisation.oci-containers.containers."ofelia" = {
    autoStart = true;
    image = "docker.io/mcuadros/ofelia:latest";
    volumes = [ "/var/run/docker.sock:/var/run/docker.sock" ];
    cmd = ["daemon" "--docker"];
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