{ config, pkgs, lib, ... }: {

  virtualisation.oci-containers.containers."socks-proxy" = {
    autoStart = true;
    image = "ghcr.io/whimbree/microsocks:latest";
    environment = { PROXY_PORT = "1080"; };
    extraOptions = [
      # networks
      "--network=host"
    ];
  };

}
