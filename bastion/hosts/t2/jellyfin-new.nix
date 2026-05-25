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
    # QEMU hangs if mem is exactly 2048 (microvm.nix issue #171).
    mem = 4096;
    hotplugMem = 2048;
    vcpu = 4;

    # Switch to QEMU for GPU passthrough. Cloud-hypervisor truncates the
    # GTX 1660 Ti's 6 GB VRAM BAR (Region 1) to 256 MB in the guest due to
    # limitations in its PCIe/BAR emulation. The NVIDIA driver sets up DMA
    # beyond that 256 MB boundary, causing Xid 32 (GPU engine exception) and
    # CUDA_ERROR_LAUNCH_FAILED on every cuCtxCreate. QEMU handles 64-bit BARs
    # of this size correctly via its Q35 machine's 64-bit MMIO window.
    hypervisor = lib.mkForce "qemu";

    # Pass through the GTX 1660 Ti (IOMMU Group 18, 2c:00.0) for NVENC/NVDEC.
    # The host must have vfio-pci bound to all four functions of the group
    # (see bastion/vfio.nix). Only the GPU function is forwarded here; the
    # audio/USB functions remain vfio-pci-bound on the host and unused.
    # microvm.nix translates this to -device vfio-pci,host=0000:2c:00.0 for QEMU.
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

    # Use the proprietary kernel module rather than the open one.
    # The open module requires GSP firmware, and GSP's CUDA context init RPC
    # deadlocks in a VFIO passthrough VM (all ffmpeg threads block on a futex
    # waiting for a GSP response that never arrives). The proprietary module
    # runs the RM on the host CPU, avoiding the RPC path entirely.
    open = false;

    # Keep the GPU in P0 at all times. Without persistenced, each NVML/CUDA
    # client triggers a P8→P0 power-state transition; in a VFIO VM that
    # transition involves ACPI/PCIe interactions that aren't fully virtualised
    # and deadlocks — hanging both the transcode and any subsequent nvidia-smi.
    # https://github.com/jellyfin/jellyfin/issues/9177
    nvidiaPersistenced = true;

    # Suspend/resume VRAM-save hooks are only meaningful on a physical desktop.
    # Leaving them enabled in a VM would break guest suspend anyway.
    powerManagement.enable = false;

    nvidiaSettings = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Disable GSP firmware and run the RM on the host CPU (the default for the
  # proprietary module). GSP is mandatory with open=true but causes CUDA
  # context init to deadlock in VFIO VMs via a silent RPC timeout.
  boot.extraModprobeConfig = ''
    options nvidia NVreg_EnableGpuFirmware=0
  '';

  # Ensure the Jellyfin container doesn't start until nvidia-persistenced has
  # set persistence mode on the GPU. Without this the container can win the
  # race at boot and hit the P8→P0 deadlock before persistenced is ready.
  systemd.services."podman-jellyfin" = {
    requires = [ "nvidia-persistenced.service" ];
    after    = [ "nvidia-persistenced.service" ];
  };

  # CDI (Container Device Interface) support — exposes /dev/nvidia* inside
  # Podman containers without needing --privileged.
  hardware.nvidia-container-toolkit.enable = true;

  # The hardware.nvidia-container-toolkit module configures Podman's cdi_spec_dirs
  # to include /var/run/cdi (which resolves to /run/cdi via the standard symlink),
  # so no manual /etc/cdi symlink is needed — the CDI spec is found automatically.

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

  # ── Temporary GPU debug packages — remove once transcoding is working ────
  environment.systemPackages = with pkgs; [
    # Process / syscall tracing
    strace           # syscall tracer — attach to hung ffmpeg/CUDA processes
    ltrace           # library call tracer — see which libcuda call is failing
    gdb              # debugger — get backtraces from stuck processes
    perf             # CPU/GPU profiling and flame graphs

    # eBPF / dynamic tracing
    bpftrace         # one-liner kernel/userspace probes (e.g. trace CUDA ioctls)
    bcc              # BPF compiler collection (opensnoop, funccount, etc.)

    # GPU monitoring
    nvtopPackages.nvidia          # htop-style GPU monitor
    config.hardware.nvidia.package  # nvidia-smi, nvidia-debugdump, nvidia-bug-report

    # CDI / container toolkit
    nvidia-container-toolkit  # nvidia-ctk — regenerate CDI spec, inspect devices

    # PCI / hardware topology
    pciutils         # lspci, setpci — inspect GPU PCIe config space and BARs
    numactl          # NUMA topology — nvidia-persistenced reported NUMA memory onlined
    hwloc            # hardware locality map (lstopo)
    dmidecode        # SMBIOS/DMI info

    # General debugging
    python3          # JSON parsing, quick scripts
    lsof             # list open file descriptors per process
    file             # identify file types
    binutils         # objdump, nm, readelf
    elfutils         # eu-addr2line, eu-stack — symbolicate crash addresses

    # Stress / validation
    stress-ng        # stress GPU memory / CPU under load
  ];
  # ─────────────────────────────────────────────────────────────────────────
}
