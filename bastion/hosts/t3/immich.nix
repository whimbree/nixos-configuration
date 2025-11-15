{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Version pinning - change these to update
  immichVersion = "release"; # or "release" for auto-update
  valkeyVersion =
    "8@sha256:81db6d39e1bba3b3ff32bd3a1b19a6d69690f94a3954ec131277b9a26b95b3aa";
  postgresVersion =
    "14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";

  # Set to true to enable auto-updates
  enableAutoUpdate = false;
in {
  microvm = {
    mem = 4096;
    hotplugMem = 4096;
    vcpu = 8;

    shares = [
      {
        source = "/services/immich";
        mountPoint = "/services/immich";
        tag = "services-immich";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/services/immich";
        mountPoint = "/ocean/services/immich";
        tag = "ocean-immich";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 40; # 40GB cache
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

  systemd.services.podman-network-immich = {
    description = "Create Immich Podman network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-immich-server.service"
      "podman-immich-machine-learning.service"
      "podman-immich-redis.service"
      "podman-immich-postgres.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists immich || \
      ${pkgs.podman}/bin/podman network create immich
    '';
  };

  # Auto-update timer (only active if enableAutoUpdate = true)
  systemd.timers.podman-auto-update-immich = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-immich = lib.mkIf enableAutoUpdate {
    description = "Auto-update Immich containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      immich-server = {
        autoStart = true;
        image = "ghcr.io/immich-app/immich-server:${immichVersion}";
        volumes = [ "/ocean/services/immich:/usr/src/app/upload" ];
        environmentFiles = [ "/services/immich/.env" ];
        dependsOn = [ "immich-redis" "immich-postgres" ];
        ports = [ "0.0.0.0:2283:2283" ];
        extraOptions = [ "--network=immich" ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      immich-machine-learning = {
        autoStart = true;
        image = "ghcr.io/immich-app/immich-machine-learning:${immichVersion}";
        volumes = [ "/services/immich/model-cache:/cache" ];
        environmentFiles = [ "/services/immich/.env" ];
        extraOptions = [ "--network=immich" ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };

      immich-redis = {
        autoStart = true;
        image = "docker.io/valkey/valkey:${valkeyVersion}";
        extraOptions = [
          "--network=immich"
          "--health-cmd=redis-cli ping || exit 1"
          "--health-interval=30s"
          "--health-timeout=3s"
          "--health-retries=3"
        ];
      };

      immich-postgres = {
        autoStart = true;
        image = "ghcr.io/immich-app/postgres:${postgresVersion}";
        environmentFiles = [ "/services/immich/.env" ];
        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        volumes = [ "/services/immich/postgres-data:/var/lib/postgresql/data" ];
        extraOptions = [ "--network=immich" "--shm-size=128m" ];
        # Don't auto-update postgres - too risky
      };
    };
  };
}
