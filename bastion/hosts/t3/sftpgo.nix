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
  sftpgoVersion = "latest";

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;

    shares = [
      {
        source = "/services/sftpgo";
        mountPoint = "/services/sftpgo";
        tag = "services-sftpgo";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/files/sftpgo";
        mountPoint = "/ocean/files/sftpgo";
        tag = "ocean-sftpgo";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 10; # 10GB cache
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

  # Auto-update timer (only active if enableAutoUpdate = true)
  systemd.timers.podman-auto-update-sftpgo = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00"; # Sunday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-sftpgo = lib.mkIf enableAutoUpdate {
    description = "Auto-update SFTPGo containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      sftpgo = {
        autoStart = true;
        image = "docker.io/drakkan/sftpgo:${sftpgoVersion}";
        volumes = [
          "/ocean/files/sftpgo:/srv/sftpgo"
          "/services/sftpgo:/var/lib/sftpgo"
        ];
        environment = { SFTPGO_WEBDAVD__BINDINGS__0__PORT = "8090"; };
        ports = [
          "0.0.0.0:8080:8080" # Web UI
          "0.0.0.0:8090:8090" # WebDAV
          "0.0.0.0:2022:2022" # SFTP
        ];
        extraOptions = [ "--user=1420:1420" ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };
}
