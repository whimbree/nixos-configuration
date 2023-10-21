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
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."filebrowser" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:latest";
    volumes = [
      "/ocean/services/filebrowser:/srv"
      "/services/filebrowser/database:/database"
      "/services/filebrowser/config:/config"
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
      "traefik.http.routers.filebrowser.rule=Host(`files.bspwr.com`, `files.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.filebrowser.entrypoints=websecure"
      "--label"
      "traefik.http.routers.filebrowser.tls=true"
      "--label"
      "traefik.http.routers.filebrowser.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.filebrowser.service=filebrowser"
      "--label"
      "traefik.http.routers.filebrowser.middlewares=default@file"
      "--label"
      "traefik.http.services.filebrowser.loadbalancer.server.port=80"
    ];
  };

  virtualisation.oci-containers.containers."filebrowser-downloads" = {
    autoStart = true;
    image = "docker.io/filebrowser/filebrowser:latest";
    volumes = [
      "/ocean/downloads:/srv:ro"
      "/services/filebrowser/database-downloads:/database"
      "/services/filebrowser/config-downloads:/config"
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
      "traefik.http.routers.filebrowser-downloads.rule=Host(`downloads.bspwr.com`, `downloads.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.filebrowser-downloads.entrypoints=websecure"
      "--label"
      "traefik.http.routers.filebrowser-downloads.tls=true"
      "--label"
      "traefik.http.routers.filebrowser-downloads.tls.certresolver=letsencrypt"
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
    image = "docker.io/filebrowser/filebrowser:latest";
    volumes = [
      "/ocean/media/shows:/srv/shows:ro"
      "/ocean/media/movies:/srv/movies:ro"
      "/ocean/media/music:/srv/music:ro"
      "/ocean/media/books:/srv/books:ro"
      "/services/filebrowser/database-media:/database"
      "/services/filebrowser/config-media:/config"
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
      "traefik.http.routers.filebrowser-media.rule=Host(`media.bspwr.com`, `media.whimsical.cloud`)"
      "--label"
      "traefik.http.routers.filebrowser-media.entrypoints=websecure"
      "--label"
      "traefik.http.routers.filebrowser-media.tls=true"
      "--label"
      "traefik.http.routers.filebrowser-media.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.filebrowser-media.service=filebrowser-media"
      "--label"
      "traefik.http.routers.filebrowser-media.middlewares=default@file"
      "--label"
      "traefik.http.services.filebrowser-media.loadbalancer.server.port=80"
    ];
  };
}
