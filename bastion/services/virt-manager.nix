{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-virt-manager = {
    enable = true;
    description = "Create virt-manager docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-virt-manager" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create virt-manager || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."virt-manager" = {
    autoStart = true;
    image = "ghcr.io/whimbree/virt-manager:latest";
    volumes = [
      "/var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock"
      "/var/lib/libvirt/images:/var/lib/libvirt/images"
    ];
    environment = {
      DARK_MODE = "true";
      HOSTS = "['qemu:///system']";
    };
    dependsOn = [ "create-network-virt-manager" ];
    extraOptions = [
      # networks
      "--network=virt-manager"
      # devices
      "--device=/dev/kvm:/dev/kvm"
      # healthcheck
      "--health-cmd"
      "wget --no-verbose --tries=1 localhost:80 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "1s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=virt-manager"
      "--label"
      "traefik.http.routers.virt-manager.rule=Host(`virt-manager.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.virt-manager.entrypoints=websecure"
      "--label"
      "traefik.http.routers.virt-manager.tls=true"
      "--label"
      "traefik.http.routers.virt-manager.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.virt-manager.service=virt-manager"
      "--label"
      "traefik.http.routers.virt-manager.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.virt-manager.loadbalancer.server.port=80"
    ];
  };
}
