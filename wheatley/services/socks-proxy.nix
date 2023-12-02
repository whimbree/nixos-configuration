{ config, pkgs, lib, ... }: {

  systemd.services.docker-create-network-socks-proxy = {
    enable = true;
    description = "Create socks-proxy docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-socks-proxy" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create socks-proxy || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."socks-proxy" = {
    autoStart = true;
    image = "ghcr.io/whimbree/microsocks:latest";
    ports = [ "100.64.0.1:1080:1080" ]; # expose only to tailscale
    dependsOn = [ "create-network-socks-proxy" "traefik" "headscale" ];
    extraOptions = [
      # networks
      "--network=socks-proxy"
    ];
  };

}
