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
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."wireguard-mullvad-usa" = {
    autoStart = true;
    image = "ghcr.io/linuxserver/wireguard:latest";
    volumes = [ "/services/mullvad-usa/wireguard:/config:Z" ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    ports = [ "4242:4242" ];
    dependsOn = [ "create-network-mullvad-usa" "modprobe-wireguard" ];
    extraOptions = [
      # cap_add
      "--cap-add=NET_ADMIN"
      # sysctls
      "--sysctl"
      "net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl"
      "net.ipv6.conf.all.disable_ipv6=0"
      # networks
      "--network=mullvad-usa"
      # healthcheck
      "--health-cmd"
      "curl --fail https://checkip.amazonaws.com | grep 142.147.89 || exit 1"
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
    ];
  };

  virtualisation.oci-containers.containers."tailscale-mullvad-usa" = {
    autoStart = true;
    image = "ghcr.io/tailscale/tailscale:latest";
    volumes = [ "/services/mullvad-usa/tailscale:/var/lib/tailscale" ];
    dependsOn = [
      "create-network-mullvad-usa"
      "modprobe-wireguard"
      "wireguard-mullvad-usa"
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
      "--net=container:wireguard-mullvad-usa"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 https://checkip.amazonaws.com | grep 142.147.89 || exit 1"
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
      "dependheal.parent=wireguard-mullvad-usa"
    ];
  };

  virtualisation.oci-containers.containers."socks-proxy-mullvad-usa" = {
    autoStart = true;
    image = "ghcr.io/bspwr/socks5-server:latest";
    environment = { PROXY_PORT = "4242"; };
    dependsOn = [ "create-network-mullvad-usa" "wireguard-mullvad-usa" ];
    extraOptions = [
      # network_mode
      "--net=container:wireguard-mullvad-usa"
      # healthcheck
      "--health-cmd"
      "curl --fail https://checkip.amazonaws.com | grep 142.147.89 || exit 1"
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
      "dependheal.parent=wireguard-mullvad-usa"
    ];
  };
}
