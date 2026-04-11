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
  natsVersion = "2-alpine";
  scyllaVersion = "2025.4";

  enableAutoUpdate = false;
in {
  microvm = {
    mem = 2048;
    hotplugMem = 2048;
    vcpu = 2;

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

  environment.systemPackages = with pkgs; [
    (python312.withPackages (ps: with ps; [
      cassandra-driver
      apsw
    ]))
  ];

  systemd.services.podman-network-fluxer = {
    description = "Create Fluxer Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-fluxer-server.service"
      "podman-fluxer-valkey.service"
      "podman-fluxer-meilisearch.service"
      "podman-fluxer-nats-core.service"
      "podman-fluxer-nats-jetstream.service"
      "podman-fluxer-scylla.service"
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
        environment = {
          FLUXER_CONFIG = "/usr/src/app/config/config.json";
          NODE_ENV = "production";
        };
        environmentFiles = [ "/services/fluxer/.env" ];
        dependsOn = [
          "fluxer-scylla"
          "fluxer-valkey"
          "fluxer-meilisearch"
          "fluxer-nats-core"
          "fluxer-nats-jetstream"
        ];
        ports = [ "0.0.0.0:8080:8080" ];
        extraOptions = [
          "--network=fluxer"
          "--init"
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

      fluxer-scylla = {
        autoStart = true;
        image = "docker.io/scylladb/scylla:${scyllaVersion}";
        volumes = [ "/services/fluxer/scylla-data:/var/lib/scylla" ];
        cmd = [
          "--authenticator" "PasswordAuthenticator"
          "--authorizer" "CassandraAuthorizer"
          "--cluster-name" "fluxer"
          "--dc" "dc1"
          "--rack" "rack1"
          # Cap memory so it doesn't fight with everything else in the microvm.
          # ScyllaDB aggressively claims all available RAM by default (like ZFS ARC)
          "--memory" "2048M"
          "--developer-mode" "1"
        ];
        extraOptions = [
          "--network=fluxer"
          "--health-cmd"
          "cqlsh -u cassandra -p cassandra -e 'SELECT now() FROM system.local' || exit 1"
          "--health-interval"
          "30s"
          "--health-timeout"
          "10s"
          "--health-retries"
          "10"
          # ScyllaDB starts faster than Cassandra but still needs some runway
          "--health-start-period"
          "30s"
        ];
      };

      fluxer-valkey = {
        autoStart = true;
        image = "docker.io/valkey/valkey:${valkeyVersion}";
        cmd = [
          "valkey-server"
          "--appendonly"
          "yes"
          "--save"
          "60"
          "1"
          "--loglevel"
          "warning"
        ];
        volumes = [ "/services/fluxer/valkey-data:/data" ];
        extraOptions = [
          "--network=fluxer"
          "--health-cmd"
          "valkey-cli ping || exit 1"
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
        environment = {
          MEILI_ENV = "production";
          MEILI_DB_PATH = "/meili_data";
          MEILI_HTTP_ADDR = "0.0.0.0:7700";
        };
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

  # Fluxer HTTP API (webhooks from LiveKit, client connections via gateway proxy)
  networking.firewall = {
    allowedTCPPorts = [ 8080 ];
  };
}
