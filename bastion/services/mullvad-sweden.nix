{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-mullvad-sweden = {
    enable = true;
    description = "Create mullvad-sweden docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-mullvad-sweden" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create mullvad-sweden || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."privoxyvpn-mullvad-sweden" = {
    autoStart = true;
    image = "docker.io/binhex/arch-privoxyvpn:latest";
    volumes = [
      "/services/mullvad-sweden/privoxyvpn:/config:Z"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      VPN_ENABLED = "yes";
      VPN_PROV = "custom";
      VPN_CLIENT = "wireguard";
      ENABLE_SOCKS = "yes";
      ENABLE_PRIVOXY = "yes";
      LAN_NETWORK = "192.168.69.0/24,172.17.0.0/12,100.64.0.0/24";
      NAME_SERVERS = "9.9.9.9,149.112.112.112,1.1.1.1,1.0.0.1";
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-mullvad-sweden" "modprobe-wireguard" ];
    extraOptions = [
      # privileged
      "--privileged"
      # sysctls
      "--sysctl"
      "net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl"
      "net.ipv6.conf.all.disable_ipv6=0"
      # networks
      "--network=mullvad-sweden"
      # healthcheck
      "--health-cmd"
      "curl --fail https://checkip.amazonaws.com | grep 185.195.233 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
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
      "traefik.docker.network=mullvad-sweden"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-http.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-http.entrypoints=mullvad-sweden-http"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-http.service=mullvad-sweden-http-serve"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-http.middlewares=proxy-allowlist@file"
      "--label"
      "traefik.tcp.services.mullvad-sweden-http-serve.loadbalancer.server.port=8118"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-socks.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-socks.entrypoints=mullvad-sweden-socks"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-socks.service=mullvad-sweden-socks-serve"
      "--label"
      "traefik.tcp.routers.mullvad-sweden-socks.middlewares=proxy-allowlist@file"
      "--label"
      "traefik.tcp.services.mullvad-sweden-socks-serve.loadbalancer.server.port=9118"
    ];
  };

  virtualisation.oci-containers.containers."tailscale-mullvad-sweden" = {
    autoStart = true;
    image = "ghcr.io/tailscale/tailscale:latest";
    volumes = [ "/services/mullvad-sweden/tailscale:/var/lib/tailscale" ];
    dependsOn = [
      "create-network-mullvad-sweden"
      "modprobe-wireguard"
      "privoxyvpn-mullvad-sweden"
    ];
    cmd = [ "tailscaled" "--tun=userspace-networking" ];
    extraOptions = [
      # cap_add
      "--cap-add=NET_ADMIN"
      # sysctls
      "--sysctl"
      "net.ipv4.ip_forward=1"
      "--sysctl"
      "net.ipv6.conf.all.forwarding=1"
      # network_mode
      "--net=container:privoxyvpn-mullvad-sweden"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 https://checkip.amazonaws.com | grep 185.195.233 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-mullvad-sweden"
    ];
  };
}
