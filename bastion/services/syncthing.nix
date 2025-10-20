{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-syncthing = {
    enable = true;
    description = "Create syncthing docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-syncthing" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create syncthing || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-syncthing = {
    after = lib.mkAfter [ "docker-create-network-syncthing.service" ];
    requires = lib.mkAfter [ "docker-create-network-syncthing.service" ];
  };
  virtualisation.oci-containers.containers."syncthing" = {
    autoStart = true;
    image = "lscr.io/linuxserver/syncthing:latest";
    volumes =
      [ "/services/syncthing/config:/config" "/merged/media/music:/music" ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    # dependsOn = [ "create-network-syncthing" ];
    ports = [
      "0.0.0.0:22000:22000/tcp" # Listening port (TCP)
      "0.0.0.0:22000:22000/udp" # Listening port (UDP)
      "0.0.0.0:21027:21027/udp" # Protocol discovery
    ];
    extraOptions = [
      # networks
      "--network=syncthing"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:8384 || exit 1"
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
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=syncthing"
      "--label"
      "traefik.http.routers.syncthing.rule=Host(`syncthing.bspwr.com`)"
      "--label"
      "traefik.http.routers.syncthing.entrypoints=websecure"
      "--label"
      "traefik.http.routers.syncthing.tls=true"
      "--label"
      "traefik.http.routers.syncthing.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.syncthing.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.syncthing.service=syncthing"
      "--label"
      "traefik.http.routers.syncthing.middlewares=default@file"
      "--label"
      "traefik.http.services.syncthing.loadbalancer.server.port=8384"
    ];
  };
}
