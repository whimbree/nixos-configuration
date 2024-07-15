{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-mullvad-usa = {
    enable = true;
    description = "Create mullvad-usa docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-mullvad-usa" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create mullvad-usa || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."privoxyvpn-mullvad-usa" = {
    autoStart = true;
    image = "docker.io/binhex/arch-privoxyvpn:latest";
    volumes = [
      "/services/mullvad-usa/privoxyvpn:/config:Z"
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
    dependsOn = [ "create-network-mullvad-usa" "modprobe-wireguard" ];
    extraOptions = [
      # privileged
      "--privileged"
      # sysctls
      "--sysctl"
      "net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl"
      "net.ipv6.conf.all.disable_ipv6=0"
      # networks
      "--network=mullvad-usa"
      # healthcheck
      "--health-cmd"
      "curl --fail https://checkip.amazonaws.com | grep 146.70.171 || exit 1"
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
      "traefik.docker.network=mullvad-usa"
      "--label"
      "traefik.tcp.routers.mullvad-usa-http.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.mullvad-usa-http.entrypoints=mullvad-usa-http"
      "--label"
      "traefik.tcp.routers.mullvad-usa-http.service=mullvad-usa-http-serve"
      "--label"
      "traefik.tcp.routers.mullvad-usa-http.middlewares=proxy-allowlist@file"
      "--label"
      "traefik.tcp.services.mullvad-usa-http-serve.loadbalancer.server.port=8118"
      "--label"
      "traefik.tcp.routers.mullvad-usa-socks.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.mullvad-usa-socks.entrypoints=mullvad-usa-socks"
      "--label"
      "traefik.tcp.routers.mullvad-usa-socks.service=mullvad-usa-socks-serve"
      "--label"
      "traefik.tcp.routers.mullvad-usa-socks.middlewares=proxy-allowlist@file"
      "--label"
      "traefik.tcp.services.mullvad-usa-socks-serve.loadbalancer.server.port=9118"
    ];
  };

  virtualisation.oci-containers.containers."tailscale-mullvad-usa" = {
    autoStart = true;
    image = "ghcr.io/tailscale/tailscale:latest";
    volumes = [ "/services/mullvad-usa/tailscale:/var/lib/tailscale" ];
    dependsOn = [
      "create-network-mullvad-usa"
      "modprobe-wireguard"
      "privoxyvpn-mullvad-usa"
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
      "--net=container:privoxyvpn-mullvad-usa"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 https://checkip.amazonaws.com | grep 146.70.171 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-mullvad-usa"
    ];
  };
}