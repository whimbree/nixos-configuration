{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-poste = {
    enable = true;
    description = "Create poste docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-poste" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create poste || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."poste-io" = {
    autoStart = true;
    image = "docker.io/analogic/poste.io:latest";
    volumes = [ "/services/poste/data:/data" ];
    environment = {
      TZ = "America/New_York";
      HTTPS = "OFF";
    };
    dependsOn = [ "create-network-poste" ];
    extraOptions = [
      # networks
      "--network=poste"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=poste"
      "--label"
      "traefik.http.routers.poste.rule=Host(`mail.bspwr.com`)"
      "--label"
      "traefik.http.routers.poste.entrypoints=websecure"
      "--label"
      "traefik.http.routers.poste.tls=true"
      "--label"
      "traefik.http.routers.poste.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.poste.service=poste"
      "--label"
      "traefik.http.routers.poste.middlewares=default@file"
      "--label"
      "traefik.http.services.poste.loadbalancer.server.port=80"
      "--label"
      "traefik.tcp.routers.poste-smtp-1.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-smtp-1.entrypoints=smtp-1"
      "--label"
      "traefik.tcp.routers.poste-smtp-1.tls=false"
      "--label"
      "traefik.tcp.routers.poste-smtp-1.service=poste-smtp-1"
      "--label"
      "traefik.tcp.services.poste-smtp-1.loadbalancer.server.port=25"
      "--label"
      "traefik.tcp.routers.poste-smtp-2.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-smtp-2.entrypoints=smtp-2"
      "--label"
      "traefik.tcp.routers.poste-smtp-2.tls=false"
      "--label"
      "traefik.tcp.routers.poste-smtp-2.service=poste-smtp-2"
      "--label"
      "traefik.tcp.services.poste-smtp-2.loadbalancer.server.port=465"
      "--label"
      "traefik.tcp.routers.poste-smtp-3.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-smtp-3.entrypoints=smtp-3"
      "--label"
      "traefik.tcp.routers.poste-smtp-3.tls=false"
      "--label"
      "traefik.tcp.routers.poste-smtp-3.service=poste-smtp-3"
      "--label"
      "traefik.tcp.services.poste-smtp-3.loadbalancer.server.port=587"
      "--label"
      "traefik.tcp.routers.poste-imap-1.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-imap-1.entrypoints=imap-1"
      "--label"
      "traefik.tcp.routers.poste-imap-1.tls=false"
      "--label"
      "traefik.tcp.routers.poste-imap-1.service=poste-imap-1"
      "--label"
      "traefik.tcp.services.poste-imap-1.loadbalancer.server.port=143"
      "--label"
      "traefik.tcp.routers.poste-imap-2.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-imap-2.entrypoints=imap-2"
      "--label"
      "traefik.tcp.routers.poste-imap-2.tls=false"
      "--label"
      "traefik.tcp.routers.poste-imap-2.service=poste-imap-2"
      "--label"
      "traefik.tcp.services.poste-imap-2.loadbalancer.server.port=993"
      "--label"
      "traefik.tcp.routers.poste-pop3-1.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-pop3-1.entrypoints=pop3-1"
      "--label"
      "traefik.tcp.routers.poste-pop3-1.tls=false"
      "--label"
      "traefik.tcp.routers.poste-pop3-1.service=poste-pop3-1"
      "--label"
      "traefik.tcp.services.poste-pop3-1.loadbalancer.server.port=110"
      "--label"
      "traefik.tcp.routers.poste-pop3-2.rule=HostSNI(`*`)"
      "--label"
      "traefik.tcp.routers.poste-pop3-2.entrypoints=pop3-2"
      "--label"
      "traefik.tcp.routers.poste-pop3-2.tls=false"
      "--label"
      "traefik.tcp.routers.poste-pop3-2.service=poste-pop3-2"
      "--label"
      "traefik.tcp.services.poste-pop3-2.loadbalancer.server.port=995"
    ];
  };
}
