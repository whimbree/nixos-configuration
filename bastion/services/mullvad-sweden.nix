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

  virtualisation.oci-containers.containers."wireguard-mullvad-sweden" = {
    autoStart = true;
    image = "ghcr.io/linuxserver/wireguard:latest";
    volumes = [ "/services/mullvad-sweden/wireguard:/config:Z" ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-mullvad-sweden" "modprobe-wireguard" ];
    extraOptions = [
      # cap_add
      "--cap-add=NET_ADMIN"
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
      "30s"
      "--health-retries"
      "10"
      "--health-timeout"
      "6s"
      "--health-start-period"
      "10s"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=mullvad-sweden"
      ### socks-proxy-mullvad-sweden
      "--label"
      "traefik.tcp.routers.mullvad-sweden.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.mullvad-sweden.entrypoints=mullvad-sweden"
      "--label"
      "traefik.tcp.routers.mullvad-sweden.tls=false"
      "--label"
      "traefik.tcp.routers.mullvad-sweden.service=mullvad-sweden"
      "--label"
      "traefik.tcp.services.mullvad-sweden.loadbalancer.server.port=6969"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."tailscale-mullvad-sweden" = {
    autoStart = true;
    image = "ghcr.io/tailscale/tailscale:latest";
    volumes = [ "/services/mullvad-sweden/tailscale:/var/lib/tailscale" ];
    dependsOn = [
      "create-network-mullvad-sweden"
      "modprobe-wireguard"
      "wireguard-mullvad-sweden"
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
      "--net=container:wireguard-mullvad-sweden"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 https://checkip.amazonaws.com | grep 185.195.233 || exit 1"
      "--health-interval"
      "30s"
      "--health-retries"
      "10"
      "--health-timeout"
      "6s"
      "--health-start-period"
      "10s"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=wireguard-mullvad-sweden"
    ];
  };

  virtualisation.oci-containers.containers."socks-proxy-mullvad-sweden" = {
    autoStart = true;
    image = "ghcr.io/bspwr/socks5-server:latest";
    environment = { PROXY_PORT = "6969"; };
    dependsOn = [ "create-network-mullvad-sweden" "wireguard-mullvad-sweden" ];
    extraOptions = [
      # network_mode
      "--net=container:wireguard-mullvad-sweden"
      # healthcheck
      "--health-cmd"
      "curl --fail https://checkip.amazonaws.com | grep 185.195.233 || exit 1"
      "--health-interval"
      "30s"
      "--health-retries"
      "10"
      "--health-timeout"
      "6s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=wireguard-mullvad-sweden"
    ];
  };
}
