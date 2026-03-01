{ config, pkgs, lib, ... }: {
  systemd.services.podman-network-headscale = {
    description = "Create headscale Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-headscale.service"
      "podman-headplane.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists headscale || \
      ${pkgs.podman}/bin/podman network create headscale
    '';
  };

  virtualisation.oci-containers.containers."headscale" = {
    autoStart = true;
    image = "docker.io/headscale/headscale:v0.25.1";
    volumes = [
      "/services/headscale/config:/etc/headscale"
      "/services/headscale/data:/var/lib/headscale"
    ];
    ports = [
      "0.0.0.0:3478:3478"
      "127.0.0.1:8080:8080"
    ];
    cmd = [ "serve" ];
    extraOptions = [
      "--network=headscale"
    ];
  };

  virtualisation.oci-containers.containers."headplane" = {
    autoStart = true;
    image = "ghcr.io/tale/headplane:0.5.10";
    volumes = [
      "/services/headplane/config.yaml:/etc/headplane/config.yaml"
      # This should match headscale.config_path in your config.yaml
      "/services/headscale/config/config.yaml:/etc/headscale/config.yaml"
      # Headplane stores its data in this directory
      "/services/headplane/data:/var/lib/headplane"
      # Mount docker socket to use docker integration
      # "/var/run/podman/podman.sock:/var/run/docker.sock:ro"
    ];
    ports = [ "127.0.0.1:3000:3000" ];
    extraOptions = [
      "--network=headscale"
    ];
  };
}
