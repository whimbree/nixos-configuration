{
  lib,
  vmName,
  mkVMNetworking,
  ...
}:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Pin the exact image currently in use. This VM has write authority over the
  # download and media trees, so updates should be reviewed and deployed rather
  # than pulled automatically.
  filebrowserImage = "docker.io/filebrowser/filebrowser@sha256:2fb157ac47d862dc11d5b9559cb3268e5589a858dd0174aa0e760ee8874b2654";
in
{
  microvm = {
    mem = 512;
    hotplugMem = 1024;
    vcpu = 2;

    # Only the small configuration/database tree uses virtiofs. The multi-TB
    # data trees are mounted over NFS below.
    shares = [
      {
        source = "/services/filebrowser";
        mountPoint = "/services/filebrowser";
        tag = "services-filebrowser";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];

    volumes = [
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        size = 1024 * 5;
        fsType = "ext4";
        autoCreate = true;
      }
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # Dedicated, least-privilege exports from the bastion host. Hard mounts and
  # the absence of nofail make the service fail closed if storage is missing.
  fileSystems = {
    "/complete/downloads" = {
      device = "10.0.0.0:/export/filebrowser/complete";
      fsType = "nfs";
      options = [
        "rw"
        "nfsvers=4.2"
        "rsize=1048576"
        "wsize=1048576"
        "hard"
        "noatime"
        "nodiratime"
        "_netdev"
      ];
    };
    "/incomplete/downloads" = {
      device = "10.0.0.0:/export/filebrowser/incomplete";
      fsType = "nfs";
      options = [
        "rw"
        "nfsvers=4.2"
        "rsize=1048576"
        "wsize=1048576"
        "hard"
        "noatime"
        "nodiratime"
        "_netdev"
      ];
    };
    "/merged/media" = {
      device = "10.0.0.0:/export/filebrowser/media";
      fsType = "nfs";
      options = [
        "rw"
        "nfsvers=4.2"
        "rsize=1048576"
        "wsize=1048576"
        "hard"
        "noatime"
        "nodiratime"
        "_netdev"
      ];
    };
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    oci-containers = {
      backend = "podman";
      containers.filebrowser-manager = {
        autoStart = true;
        image = filebrowserImage;

        # Bypass the s6 wrapper so the service has the exact supplementary
        # group required by existing downloads (numeric GID 83).
        entrypoint = "/bin/filebrowser";
        cmd = [
          "-c"
          "/config/settings.json"
        ];
        user = "1420:1420";

        volumes = [
          "/complete/downloads:/srv/complete/downloads"
          "/incomplete/downloads:/srv/incomplete/downloads"
          "/merged/media:/srv/merged/media"
          "/services/filebrowser/media-config/filebrowser.db:/database/filebrowser.db"
          "/services/filebrowser/media-config/settings.json:/config/settings.json"
        ];
        environment.TZ = "America/New_York";
        ports = [ "0.0.0.0:8080:80" ];
        extraOptions = [
          "--group-add=83"
          "--security-opt=no-new-privileges"
        ];
      };
    };
  };

  users.users.fileshare = {
    createHome = false;
    isSystemUser = true;
    group = "fileshare";
    uid = 1420;
  };
  users.groups.fileshare.gid = 1420;

  # Never start File Browser against empty local directories if NFS is absent.
  systemd.services.podman-filebrowser-manager.unitConfig.RequiresMountsFor =
    "/complete/downloads /incomplete/downloads /merged/media";
}
