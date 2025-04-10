{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-arr = {
    enable = true;
    description = "Create arr docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-arr" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create arr || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  # vpn port forward: 46278
  virtualisation.oci-containers.containers."delugevpn" = {
    autoStart = true;
    image = "docker.io/binhex/arch-delugevpn:latest";
    volumes = [
      "/services/arr/delugevpn:/config"
      "/ocean/downloads:/downloads:z"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      VPN_ENABLED = "yes";
      VPN_PROV = "custom";
      VPN_CLIENT = "wireguard";
      ENABLE_PRIVOXY = "yes";
      LAN_NETWORK = "192.168.69.0/24,172.17.0.0/12,100.64.0.0/24";
      NAME_SERVERS = "9.9.9.9,149.112.112.112,1.1.1.1,1.0.0.1";
      DELUGE_DAEMON_LOG_LEVEL = "info";
      DELUGE_WEB_LOG_LEVEL = "info";
      DELUGE_ENABLE_WEBUI_PASSWORD = "yes";
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" "modprobe-wireguard" ];
    extraOptions = [
      # privileged
      "--privileged"
      # sysctls
      "--sysctl"
      "net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl"
      "net.ipv6.conf.all.disable_ipv6=0"
      # networks
      "--network=arr"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:8112 && curl --fail https://checkip.amazonaws.com | grep 62.102.148 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "60"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=arr"
      ### deluge
      "--label"
      "traefik.http.routers.deluge.rule=Host(`deluge.bspwr.com`)"
      "--label"
      "traefik.http.routers.deluge.entrypoints=websecure"
      "--label"
      "traefik.http.routers.deluge.tls=true"
      "--label"
      "traefik.http.routers.deluge.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.deluge.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.deluge.service=deluge"
      "--label"
      "traefik.http.routers.deluge.middlewares=default@file"
      "--label"
      "traefik.http.services.deluge.loadbalancer.server.port=8112"
      ### sonarr
      "--label"
      "traefik.http.routers.sonarr.rule=Host(`sonarr.bspwr.com`)"
      "--label"
      "traefik.http.routers.sonarr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.sonarr.tls=true"
      "--label"
      "traefik.http.routers.sonarr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.sonarr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.sonarr.service=sonarr"
      "--label"
      "traefik.http.routers.sonarr.middlewares=default@file"
      "--label"
      "traefik.http.services.sonarr.loadbalancer.server.port=8989"
      ### radarr
      "--label"
      "traefik.http.routers.radarr.rule=Host(`radarr.bspwr.com`)"
      "--label"
      "traefik.http.routers.radarr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.radarr.tls=true"
      "--label"
      "traefik.http.routers.radarr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.radarr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.radarr.service=radarr"
      "--label"
      "traefik.http.routers.radarr.middlewares=default@file"
      "--label"
      "traefik.http.services.radarr.loadbalancer.server.port=7878"
      ### lidarr
      "--label"
      "traefik.http.routers.lidarr.rule=Host(`lidarr.bspwr.com`)"
      "--label"
      "traefik.http.routers.lidarr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.lidarr.tls=true"
      "--label"
      "traefik.http.routers.lidarr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.lidarr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.lidarr.service=lidarr"
      "--label"
      "traefik.http.routers.lidarr.middlewares=default@file"
      "--label"
      "traefik.http.services.lidarr.loadbalancer.server.port=8686"
      ### readarr
      "--label"
      "traefik.http.routers.readarr.rule=Host(`readarr.bspwr.com`)"
      "--label"
      "traefik.http.routers.readarr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.readarr.tls=true"
      "--label"
      "traefik.http.routers.readarr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.readarr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.readarr.service=readarr"
      "--label"
      "traefik.http.routers.readarr.middlewares=default@file"
      "--label"
      "traefik.http.services.readarr.loadbalancer.server.port=8787"
      ### prowlarr
      "--label"
      "traefik.http.routers.prowlarr.rule=Host(`prowlarr.bspwr.com`)"
      "--label"
      "traefik.http.routers.prowlarr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.prowlarr.tls=true"
      "--label"
      "traefik.http.routers.prowlarr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.prowlarr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.prowlarr.service=prowlarr"
      "--label"
      "traefik.http.routers.prowlarr.middlewares=default@file"
      "--label"
      "traefik.http.services.prowlarr.loadbalancer.server.port=9696"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."sonarr" = {
    autoStart = true;
    image = "ghcr.io/linuxserver/sonarr:latest";
    volumes = [
      "/services/arr/sonarr:/config:Z"
      "/merged/media/shows:/shows:z"
      "/ocean/downloads:/downloads:z"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" "delugevpn" ];
    extraOptions = [
      # network_mode
      "--net=container:delugevpn"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:8989 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=delugevpn"
    ];
  };

  virtualisation.oci-containers.containers."radarr" = {
    autoStart = true;
    image = "ghcr.io/linuxserver/radarr:latest";
    volumes = [
      "/services/arr/radarr:/config:Z"
      "/merged/media/movies:/movies:z"
      "/ocean/downloads:/downloads:z"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" "delugevpn" ];
    extraOptions = [
      # network_mode
      "--net=container:delugevpn"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:7878 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=delugevpn"
    ];
  };

  virtualisation.oci-containers.containers."bazarr" = {
    autoStart = true;
    image = "lscr.io/linuxserver/bazarr:latest";
    volumes = [
      "/services/arr/bazarr:/config:Z"
      "/merged/media/movies:/movies:z"
      "/merged/media/shows:/shows:z"
      "/ocean/downloads:/downloads:z"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" ];
    extraOptions = [
      # networks
      "--network=arr"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:6767 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.http.routers.bazarr.rule=Host(`bazarr.bspwr.com`)"
      "--label"
      "traefik.http.routers.bazarr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.bazarr.tls=true"
      "--label"
      "traefik.http.routers.bazarr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.bazarr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.bazarr.service=bazarr"
      "--label"
      "traefik.http.routers.bazarr.middlewares=default@file"
      "--label"
      "traefik.http.services.bazarr.loadbalancer.server.port=6767"
    ];
  };

  virtualisation.oci-containers.containers."lidarr" = {
    autoStart = true;
    image = "lscr.io/linuxserver/lidarr:latest";
    volumes = [
      "/services/arr/lidarr:/config:Z"
      "/merged/media/music:/music:z"
      "/ocean/downloads:/downloads:z"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" "delugevpn" ];
    extraOptions = [
      # network_mode
      "--net=container:delugevpn"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:8686 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=delugevpn"
    ];
  };

  virtualisation.oci-containers.containers."readarr" = {
    autoStart = true;
    image = "lscr.io/linuxserver/readarr:develop";
    volumes = [
      "/services/arr/readarr:/config:Z"
      "/merged/media/books:/books:z"
      "/ocean/downloads:/downloads:z"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" "delugevpn" ];
    extraOptions = [
      # network_mode
      "--net=container:delugevpn"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:8787 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=delugevpn"
    ];
  };

  virtualisation.oci-containers.containers."prowlarr" = {
    autoStart = true;
    image = "lscr.io/linuxserver/prowlarr:develop";
    volumes = [ "/services/arr/prowlarr:/config:Z" ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-arr" "delugevpn" ];
    extraOptions = [
      # network_mode
      "--net=container:delugevpn"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:9696 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=delugevpn"
    ];
  };

  virtualisation.oci-containers.containers."jellyseerr" = {
    autoStart = true;
    image = "docker.io/fallenbagel/jellyseerr:latest";
    volumes = [ "/services/arr/jellyseerr:/app/config:Z" ];
    environment = { TZ = "America/New_York"; };
    dependsOn = [ "create-network-arr" ];
    extraOptions = [
      # networks
      "--network=arr"
      # healthcheck
      "--health-cmd"
      "wget --no-verbose --tries=1 --spider localhost:5055 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "4s"
      "--health-start-period"
      "10s"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=arr"
      "--label"
      "traefik.http.routers.jellyseerr.rule=Host(`jellyseerr.bspwr.com`)"
      "--label"
      "traefik.http.routers.jellyseerr.entrypoints=websecure"
      "--label"
      "traefik.http.routers.jellyseerr.tls=true"
      "--label"
      "traefik.http.routers.jellyseerr.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.jellyseerr.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.jellyseerr.service=jellyseerr"
      "--label"
      "traefik.http.routers.jellyseerr.middlewares=default@file"
      "--label"
      "traefik.http.services.jellyseerr.loadbalancer.server.port=5055"
    ];
  };

  virtualisation.oci-containers.containers."flaresolverr" = {
    autoStart = true;
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    environment = { TZ = "America/New_York"; };
    dependsOn = [ "create-network-arr" ];
    extraOptions = [
      # networks
      "--network=arr"
      # ip
      "--ip=172.23.128.3"
      # labels
      "--label"
      "dependheal.enable=true"
    ];
  };
}
