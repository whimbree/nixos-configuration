{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-filebrowser = {
    enable = true;
    description = "Create filebrowser docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-filebrowser" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create filebrowser || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."filebrowser-downloads" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:s6";
    volumes = [
      "/ocean/downloads:/srv:ro"
      "/services/filebrowser/downloads-config/filebrowser.db:/database/filebrowser.db"
      "/services/filebrowser/downloads-config/settings.json:/config/settings.json"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-filebrowser" ];
    extraOptions = [
      # networks
      "--network=filebrowser"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=filebrowser"
      "--label"
      "traefik.http.routers.filebrowser-downloads.rule=Host(`downloads.bspwr.com`)"
      "--label"
      "traefik.http.routers.filebrowser-downloads.entrypoints=websecure"
      "--label"
      "traefik.http.routers.filebrowser-downloads.tls=true"
      "--label"
      "traefik.http.routers.filebrowser-downloads.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.filebrowser-downloads.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.filebrowser-downloads.service=filebrowser-downloads"
      "--label"
      "traefik.http.routers.filebrowser-downloads.middlewares=default@file"
      "--label"
      "traefik.http.services.filebrowser-downloads.loadbalancer.server.port=80"
    ];
  };

  virtualisation.oci-containers.containers."filebrowser-media" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:s6";
    volumes = [
      "/merged/media/shows:/srv/shows:ro"
      "/merged/media/movies:/srv/movies:ro"
      "/merged/media/music:/srv/music:ro"
      "/merged/media/books:/srv/books:ro"
      "/services/filebrowser/media-config/filebrowser.db:/database/filebrowser.db"
      "/services/filebrowser/media-config/settings.json:/config/settings.json"
    ];
    environment = {
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    dependsOn = [ "create-network-filebrowser" ];
    extraOptions = [
      # networks
      "--network=filebrowser"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=filebrowser"
      "--label"
      "traefik.http.routers.filebrowser-media.rule=Host(`media.bspwr.com`)"
      "--label"
      "traefik.http.routers.filebrowser-media.entrypoints=websecure"
      "--label"
      "traefik.http.routers.filebrowser-media.tls=true"
      "--label"
      "traefik.http.routers.filebrowser-media.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.filebrowser-media.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.filebrowser-media.service=filebrowser-media"
      "--label"
      "traefik.http.routers.filebrowser-media.middlewares=default@file"
      "--label"
      "traefik.http.services.filebrowser-media.loadbalancer.server.port=80"
    ];
  };
}
