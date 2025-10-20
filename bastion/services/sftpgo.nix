{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-sftpgo = {
    enable = true;
    description = "Create sftpgo docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-sftpgo" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create sftpgo || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-sftpgo = {
    after = lib.mkAfter [ "docker-create-network-sftpgo.service" ];
    requires = lib.mkAfter [ "docker-create-network-sftpgo.service" ];
  };
  virtualisation.oci-containers.containers."sftpgo" = {
    autoStart = true;
    image = "docker.io/drakkan/sftpgo:latest";
    volumes =
      [ "/ocean/files/sftpgo:/srv/sftpgo" "/services/sftpgo:/var/lib/sftpgo" ];
    environment = { SFTPGO_WEBDAVD__BINDINGS__0__PORT = "8090"; };
    # dependsOn = [ "create-network-sftpgo" ];
    extraOptions = [
      "--user"
      "1420:1420"
      # networks
      "--network=sftpgo"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=sftpgo"
      "--label"
      "traefik.http.routers.sftpgo-webdav.rule=Host(`files-webdav.bspwr.com`)"
      "--label"
      "traefik.http.routers.sftpgo-webdav.entrypoints=websecure"
      "--label"
      "traefik.http.routers.sftpgo-webdav.tls=true"
      "--label"
      "traefik.http.routers.sftpgo-webdav.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.sftpgo-webdav.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.sftpgo-webdav.service=sftpgo-webdav"
      "--label"
      "traefik.http.routers.sftpgo-webdav.middlewares=default@file"
      "--label"
      "traefik.http.services.sftpgo-webdav.loadbalancer.server.port=8090"
      "--label"
      "traefik.http.routers.sftpgo-ui.rule=Host(`files.bspwr.com`)"
      "--label"
      "traefik.http.routers.sftpgo-ui.entrypoints=websecure"
      "--label"
      "traefik.http.routers.sftpgo-ui.tls=true"
      "--label"
      "traefik.http.routers.sftpgo-ui.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.sftpgo-ui.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.sftpgo-ui.service=sftpgo-ui"
      "--label"
      "traefik.http.routers.sftpgo-ui.middlewares=default@file"
      "--label"
      "traefik.http.services.sftpgo-ui.loadbalancer.server.port=8080"
    ];
  };
}
