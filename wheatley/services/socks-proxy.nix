{ config, pkgs, lib, ... }: {

  virtualisation.oci-containers.containers."socks-proxy" = {
    autoStart = true;
    image = "ghcr.io/whimbree/microsocks:latest";
    extraOptions = [
      # networks
      "--network=host"
    ];
  };

}
