{ config, pkgs, lib, ... }: {

  virtualisation.oci-containers.containers."coturn" = {
    autoStart = true;
    image = "docker.io/coturn/coturn:latest";
    volumes = [
      "/services/nextcloud/coturn/turnserver.conf:/etc/coturn/turnserver.conf:ro"
    ];
    ports = [ "3478:3478" "3478:3478/udp" ];
  };

}
