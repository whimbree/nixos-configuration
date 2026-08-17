{
  config,
  lib,
  pkgs,
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
  # https://github.com/gtsteffaniak/filebrowser/pkgs/container/filebrowser/1136370078?tag=beta
  # ghcr.io/gtsteffaniak/filebrowser:beta
  filebrowserImage = "ghcr.io/gtsteffaniak/filebrowser:beta@sha256:cd9997417eb468ec6a48a20939fe3ee5e1b007bdec823575980957109dfbd3d7";

  # LinuxServer's single-application Double Commander desktop, streamed to the
  # browser by Selkies. Keep it pinned because it has the same write authority
  # over the media trees as Quantum.
  doubleCommanderImage = "lscr.io/linuxserver/doublecommander:latest@sha256:fa08951923bd0d05437b2dbb95691dd491c0ba55eb18d52e8a57cb7584653be0";

  # LinuxServer changes its `abc` account to PUID/PGID during initialization.
  # Add the downloads group afterwards, before services start, so the GUI gets
  # the same supplementary GID 83 that Quantum already uses.
  doubleCommanderInit = pkgs.writeTextFile {
    name = "doublecommander-downloads-group";
    executable = true;
    text = ''
      #!/bin/sh
      set -eu

      group_line="$(getent group 83 || true)"
      if [ -n "$group_line" ]; then
        group_name="$(printf '%s\n' "$group_line" | cut -d: -f1)"
      else
        group_name=downloads
        groupadd --gid 83 "$group_name"
      fi

      usermod --append --groups "$group_name" abc
      id -G abc | tr ' ' '\n' | grep -qx 83
    '';
  };

  # Quantum uses YAML configuration and SQLite, not the archived File Browser
  # project's JSON/BoltDB layout. A root viewable rule keeps each multi-TB
  # source browsable while deliberately excluding it from Quantum's index.
  filebrowserConfig = pkgs.writeText "filebrowser-quantum.yaml" ''
    http:
      port: 8080
      listen: "0.0.0.0"
      baseURL: "/"
      externalUrl: "https://media.bspwr.com"
      internalUrl: "http://127.0.0.1:8080"
      disableWebDAV: true
      trustProxyHeaders: true
    server:
      disableUpdateCheck: true
      disablePreviews: true
      disableTypeDetectionByHeader: true
      cacheDir: "/home/filebrowser/data/cache"
      cacheDirCleanup: true
      database:
        path: "/home/filebrowser/data/database.sqlite"
      filesystem:
        createFilePermission: "664"
        createDirectoryPermission: "775"
      logging:
        - levels: "info|warning|error"
          output: "stdout"
          noColors: true
      sources:
        - path: "/complete/downloads"
          name: "Complete Downloads"
          config:
            private: true
            defaultEnabled: true
            rules:
              - folderPath: "/"
                viewable: true
        - path: "/incomplete/downloads"
          name: "Incomplete Downloads"
          config:
            private: true
            defaultEnabled: true
            rules:
              - folderPath: "/"
                viewable: true
        - path: "/merged/media"
          name: "Merged Media"
          config:
            private: true
            defaultEnabled: true
            rules:
              - folderPath: "/"
                viewable: true
    auth:
      tokenExpirationHours: 2
      adminUsername: "admin"
      methods:
        noauth: false
        password:
          enabled: true
          minLength: 12
          signup: false
        passkey:
          enabled: false
    frontend:
      name: "Media File Manager"
      disableDefaultLinks: true
  '';
in
{
  microvm = {
    # Quantum is tiny; the additional Selkies desktop needs more breathing
    # room. Together with hotpluggedMem this gives the guest 2 GiB at boot.
    mem = 1024;
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
      containers.filebrowser = {
        autoStart = true;
        image = filebrowserImage;

        # Run Quantum as the existing fileshare identity, with the downloads
        # group as a supplement. Numeric IDs pass through NFS unchanged.
        user = "1420:1420";

        volumes = [
          "/complete/downloads:/complete/downloads"
          "/incomplete/downloads:/incomplete/downloads"
          "/merged/media:/merged/media"
          "/services/filebrowser/quantum-data:/home/filebrowser/data"
          "${filebrowserConfig}:/etc/filebrowser/config.yaml:ro"
        ];
        environment = {
          FILEBROWSER_CONFIG = "/etc/filebrowser/config.yaml";
          TZ = "America/New_York";
        };
        environmentFiles = [ config.sops.templates."filebrowser-env".path ];
        ports = [ "0.0.0.0:8080:8080" ];
        extraOptions = [
          "--group-add=83"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
        ];
      };

      containers.doublecommander = {
        autoStart = true;
        image = doubleCommanderImage;

        # LinuxServer's init runs as root, then launches the desktop as `abc`
        # with these IDs. The custom init hook adds supplementary GID 83.
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
          UMASK = "002";
          TITLE = "Media File Manager";
          START_DOCKER = "false";
          HARDEN_DESKTOP = "true";
          RESTART_APP = "true";
          SELKIES_ENABLE_SHARING = "false|locked";
          SELKIES_ENABLE_COLLAB = "false|locked";
          SELKIES_ENABLE_SHARED = "false|locked";
          SELKIES_CLIPBOARD_ENABLED = "false|locked";
          SELKIES_AUDIO_ENABLED = "false|locked";
          SELKIES_MICROPHONE_ENABLED = "false|locked";
          SELKIES_GAMEPAD_ENABLED = "false|locked";
          SELKIES_UI_SIDEBAR_SHOW_SHARING = "false|locked";
          SELKIES_UI_SIDEBAR_SHOW_CLIPBOARD = "false|locked";
          SELKIES_UI_SIDEBAR_SHOW_AUDIO_SETTINGS = "false|locked";
          SELKIES_UI_SIDEBAR_SHOW_GAMEPADS = "false|locked";
          SELKIES_UI_SIDEBAR_SHOW_GAMING_MODE = "false|locked";
        };
        environmentFiles = [ config.sops.templates."doublecommander-env".path ];

        volumes = [
          "/complete/downloads:/data/complete"
          "/incomplete/downloads:/data/incomplete"
          "/merged/media:/data/media"
          "/services/filebrowser/doublecommander-config:/config"
          "${doubleCommanderInit}:/custom-cont-init.d/10-downloads-group:ro"
        ];
        ports = [ "0.0.0.0:3000:3000" ];
        extraOptions = [
          "--shm-size=1g"
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

  # SOPS is the authority for both browser-facing credentials. Updating an
  # encrypted value and restarting its container rotates that credential.
  sops = {
    secrets."filebrowser_admin_password" = { };
    secrets."doublecommander_password" = { };
    templates."filebrowser-env".content = ''
      FILEBROWSER_ADMIN_PASSWORD=${config.sops.placeholder."filebrowser_admin_password"}
    '';
    templates."doublecommander-env".content = ''
      CUSTOM_USER=admin
      PASSWORD=${config.sops.placeholder."doublecommander_password"}
    '';
  };

  systemd.tmpfiles.rules = [
    "d /services/filebrowser/quantum-data 0700 1420 1420 -"
    "d /services/filebrowser/doublecommander-config 0700 1420 1420 -"
  ];

  # Never start the write-authority service against empty local directories if
  # any NFS mount is absent.
  systemd.services.podman-filebrowser.unitConfig.RequiresMountsFor =
    "/complete/downloads /incomplete/downloads /merged/media";
  systemd.services.podman-doublecommander.unitConfig.RequiresMountsFor =
    "/complete/downloads /incomplete/downloads /merged/media";
}
