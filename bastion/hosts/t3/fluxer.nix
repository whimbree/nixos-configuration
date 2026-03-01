{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Version pinning
  fluxerServerVersion = "latest";
  valkeyVersion = "8.0.6-alpine";
  meilisearchVersion = "v1.14";
  livekitVersion = "v1.9.11";
  natsVersion = "2-alpine";

  enableAutoUpdate = false;
in {
  microvm = {
    mem = 4096;
    hotplugMem = 4096;
    vcpu = 4;

    shares = [{
      source = "/services/fluxer";
      mountPoint = "/services/fluxer";
      tag = "services-fluxer";
      proto = "virtiofs";
      securityModel = "mapped-xattr";
    }];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 40;
      fsType = "ext4";
      autoCreate = true;
    }];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  systemd.services.podman-network-fluxer = {
    description = "Create Fluxer Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-fluxer-server.service"
      "podman-fluxer-valkey.service"
      "podman-fluxer-meilisearch.service"
      "podman-fluxer-livekit.service"
      "podman-fluxer-nats-core.service"
      "podman-fluxer-nats-jetstream.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists fluxer || \
      ${pkgs.podman}/bin/podman network create fluxer
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      fluxer-server = {
        autoStart = true;
        image =
          "ghcr.io/whimbree/fluxer-server:${fluxerServerVersion}";
        volumes = [
          "/services/fluxer/config:/usr/src/app/config:ro"
          "/services/fluxer/data:/usr/src/app/data"
        ];
        environmentFiles = [ "/services/fluxer/.env" ];
        dependsOn = [
          "fluxer-valkey"
          "fluxer-meilisearch"
          "fluxer-nats-core"
          "fluxer-nats-jetstream"
        ];
        ports = [ "0.0.0.0:8080:8080" ];
        extraOptions = [
          "--network=fluxer"
          "--health-cmd"
          "curl --fail localhost:8080/_health || exit 1"
          "--health-interval"
          "30s"
          "--health-retries"
          "5"
          "--health-timeout"
          "10s"
          "--health-start-period"
          "30s"
        ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      fluxer-valkey = {
        autoStart = true;
        image = "docker.io/valkey/valkey:${valkeyVersion}";
        extraOptions = [
          "--network=fluxer"
          "--health-cmd"
          "redis-cli ping || exit 1"
          "--health-interval"
          "30s"
          "--health-timeout"
          "3s"
          "--health-retries"
          "3"
        ];
      };

      fluxer-meilisearch = {
        autoStart = true;
        image = "docker.io/getmeili/meilisearch:${meilisearchVersion}";
        volumes = [ "/services/fluxer/meili-data:/meili_data" ];
        environmentFiles = [ "/services/fluxer/.env" ];
        extraOptions = [
          "--network=fluxer"
          "--health-cmd"
          "curl --fail localhost:7700/health || exit 1"
          "--health-interval"
          "30s"
          "--health-timeout"
          "5s"
          "--health-retries"
          "3"
        ];
      };

      fluxer-livekit = {
        autoStart = true;
        image = "docker.io/livekit/livekit-server:${livekitVersion}";
        volumes =
          [ "/services/fluxer/config/livekit.yaml:/etc/livekit.yaml:ro" ];
        cmd = [ "--config" "/etc/livekit.yaml" ];
        ports = [
          "0.0.0.0:7880:7880"
          "0.0.0.0:7881:7881/tcp"
          "0.0.0.0:3478:3478/udp"
          "0.0.0.0:50000-50100:50000-50100/udp"
        ];
        extraOptions = [ "--network=fluxer" ];
      };

      fluxer-nats-core = {
        autoStart = true;
        image = "docker.io/nats:${natsVersion}";
        extraOptions = [ "--network=fluxer" ];
      };

      fluxer-nats-jetstream = {
        autoStart = true;
        image = "docker.io/nats:${natsVersion}";
        cmd = [ "--jetstream" "--store_dir" "/data" "-p" "4223" ];
        volumes = [ "/services/fluxer/nats-data:/data" ];
        extraOptions = [ "--network=fluxer" ];
      };
    };
  };

  # LiveKit media transport ports (7881, 3478, 50000-50100) need host-level
  # forwarding from the bastion's public IP to this microvm for voice/video.
  networking.firewall = {
    allowedTCPPorts = [ 8080 7880 7881 ];
    allowedUDPPorts = [ 3478 ];
    allowedUDPPortRanges = [{
      from = 50000;
      to = 50100;
    }];
  };
}
