{ config, lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Version pinning - change these to update
  jellyfinVersion = "nightly";

  # Set to true to enable auto-updates
  enableAutoUpdate = false;
in {
  microvm = {
    mem = 2048;
    hotplugMem = 2048;
    vcpu = 4;

    # Pass through the GTX 1660 Ti (IOMMU Group 18, 2c:00.0) for NVENC/NVDEC.
    # The host must have vfio-pci bound to all four functions of the group
    # (see bastion/vfio.nix). Only the GPU function is forwarded here; the
    # audio/USB functions remain vfio-pci-bound on the host and unused.
    devices = [{
      bus = "pci";
      path = "0000:2c:00.0";
    }];

    # Share VPN config from host
    shares = [{
      source = "/services/jellyfin-new/config";
      mountPoint = "/services/jellyfin/config";
      tag = "jellyfin";
      proto = "virtiofs";
      securityModel = "mapped-xattr";
    }];

    volumes = [
      {
        image = "jellyfin-cache.img";
        mountPoint = "/var/cache/jellyfin";
        size = 1024 * 100; # 100GB cache
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        size = 1024 * 40; # 10GB cache
        fsType = "ext4";
        autoCreate = true;
      }
    ];
  };

  fileSystems."/merged/media/shows" = {
    device = "10.0.0.0:/export/media/shows";
    fsType = "nfs";
    options = [
      "ro"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/merged/media/movies" = {
    device = "10.0.0.0:/export/media/movies";
    fsType = "nfs";
    options = [
      "ro"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/merged/media/music" = {
    device = "10.0.0.0:/export/media/music";
    fsType = "nfs";
    options = [
      "ro"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/merged/media/books" = {
    device = "10.0.0.0:/export/media/books";
    fsType = "nfs";
    options = [
      "ro"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/merged/media/xxx" = {
    device = "10.0.0.0:/export/media/xxx";
    fsType = "nfs";
    options = [
      "ro"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "hard"
      "noatime"
      "nodiratime"
    ];
  };

  boot.kernelParams = [ "mitigations=off" ];

  # NVIDIA driver is unfree; mkMicroVM doesn't pull in profiles/common.nix.
  nixpkgs.config.allowUnfree = true;

  # NVIDIA driver — firmware blobs are required; override the microvm-defaults
  # setting that disables redistributable firmware.
  hardware.enableRedistributableFirmware = lib.mkForce true;

  hardware.graphics.enable = true;

  # Declaring the video driver here (even without X11 enabled) triggers NixOS
  # to load the NVIDIA kernel modules and satisfies the nvidia-container-toolkit
  # assertion that requires either this, hardware.nvidia.datacenter.enable, or
  # suppressNvidiaDriverAssertion.
  # https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/nvidia/
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Modesetting is required for the driver to initialise properly in a
    # headless (no display) context so NVENC/NVDEC are accessible.
    modesetting.enable = true;

    # GTX 1660 Ti is Turing (TU116) — open module is supported as of R570+.
    # https://github.com/NVIDIA/open-gpu-kernel-modules/blob/main/README.md
    open = true;

    nvidiaSettings = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # CDI (Container Device Interface) support — exposes /dev/nvidia* inside
  # Podman containers without needing --privileged.
  hardware.nvidia-container-toolkit.enable = true;

  # NixOS generates the CDI spec in /run/cdi/ but Podman only searches /etc/cdi/
  # and /var/run/cdi/, so --device=nvidia.com/gpu=all is silently ignored without this.
  # https://discourse.nixos.org/t/nvidia-ctk-shows-gpu-but-podman-doesnt-find-it-for-passthrough/65869
  environment.etc."cdi/nvidia-container-toolkit.json".source = "/run/cdi/nvidia-container-toolkit.json";

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
  systemd.timers.podman-auto-update-jellyfin = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed 03:00"; # Wednesday 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update-jellyfin = lib.mkIf enableAutoUpdate {
    description = "Auto-update jellyfin containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
  };

  # create fileshare user for services
  users.users.fileshare = {
    createHome = false;
    isSystemUser = true;
    group = "fileshare";
    uid = 1420;
  };
  users.groups.fileshare = {
    gid = 1420;
    members = [ "fileshare" ];
  };

  systemd.services.jellyfin-cache-permissions = {
    description = "Set permissions on Jellyfin cache";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      FOLDER=/var/cache/jellyfin

      # Change ownership recursively
      ${pkgs.coreutils}/bin/chown -R fileshare:fileshare "$FOLDER"

      # Change permissions
      ${pkgs.coreutils}/bin/chmod -R 770 "$FOLDER"
    '';
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      jellyfin = {
        autoStart = true;
        image = "lscr.io/linuxserver/jellyfin:${jellyfinVersion}";
        volumes = [
          "/services/jellyfin/config:/config"
          "/var/cache/jellyfin:/config/cache"
          "/merged/media/shows:/data/shows:ro"
          "/merged/media/movies:/data/movies:ro"
          "/merged/media/music:/data/music:ro"
          "/merged/media/books:/data/books:ro"
          "/merged/media/xxx:/data/xxx:ro"
        ];
        environment = {
          PUID = "1420";
          PGID = "1420";
          TZ = "America/New_York";
          # Tell the NVIDIA runtime which GPU to expose and which driver
          # capabilities to enable. The linuxserver s6 init also reads these.
          # https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/nvidia/
          NVIDIA_VISIBLE_DEVICES = "all";
          NVIDIA_DRIVER_CAPABILITIES = "all";
        };
        ports = [ "0.0.0.0:8096:8096" ];
        extraOptions = [
          # NVIDIA GPU access via CDI (set up by hardware.nvidia-container-toolkit)
          "--device=nvidia.com/gpu=all"
          # /dev/nvidia* are root:video 0660; the linuxserver abc user (PUID 1420)
          # runs ffmpeg and needs the video group or NVML returns EPERM.
          # https://github.com/linuxserver/docker-jellyfin/issues/238
          "--group-add=video"
          # healthcheck
          "--health-cmd"
          "curl --fail localhost:8096 || exit 1"
          "--health-interval"
          "10s"
          "--health-retries"
          "30"
          "--health-timeout"
          "10s"
          "--health-start-period"
          "10s"
        ] ++ lib.optionals enableAutoUpdate
          [ "--label=io.containers.autoupdate=registry" ];
      };
    };
  };

  # Override firewall to allow Jellyfin
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
