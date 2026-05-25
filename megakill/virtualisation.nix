{ pkgs, config, lib, machineConfig, ... }: {

  imports = [
    ../modules/vfio.nix
    ./modules/kvmfr-options.nix
  ];

  virtualisation = {

    # Podman: rootless OCI container runtime (Docker-compatible CLI).
    # Docker is not used in this homelab — Podman runs containers without a
    # daemon and never requires root for normal operation.
    podman = {
      enable = true;
      dockerCompat = true; # symlink `docker` → `podman` for compatibility
      autoPrune.enable = true;
    };

    libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm;
        vhostUserPackages = [ pkgs.virtiofsd ];
        # swtpm provides a software TPM 2.0, required for Windows 11 guests.
        swtpm.enable = true;
        # runAsRoot = false: QEMU processes run as the invoking user, not root.
        # Requires the device ACL list below to grant access to /dev/kvm etc.
        runAsRoot = false;
        # Devices accessible to non-root QEMU processes.
        # /dev/kvmfr0: Looking Glass shared memory (kvmfr kernel module)
        # /dev/vfio/*: VFIO container and the RTX 3090's IOMMU group
        verbatimConfig = ''
          cgroup_device_acl = [
            "/dev/null", "/dev/full", "/dev/zero",
            "/dev/random", "/dev/urandom",
            "/dev/ptmx", "/dev/kvm",
            "/dev/kvmfr0",
            "/dev/vfio/vfio", "/dev/vfio/${machineConfig.gpu.nvidia.vfioGroup}"
          ]
        '';
      };
    };

    # kvmfr: kernel module that creates a shared memory device between the
    # host and a Looking Glass VM. Looking Glass streams the VM's framebuffer
    # over this device at near-zero latency without a physical cable.
    kvmfr = {
      enable = true;
      shm = {
        enable = true;
        size = 512; # MB — must be large enough for the VM's display resolution
        user = "root";
        group = "kvm";
        mode = "0660";
      };
    };

    # USB redirection: lets SPICE clients (virt-manager) hot-plug USB devices
    # into a running VM without manual udev rules.
    spiceUSBRedirection.enable = true;
  };

  # Base VFIO config — active on every boot.
  # IOMMU and MSR handling are always beneficial; no devices are bound and
  # Nvidia is not blacklisted here. The specialisation layers those on top.
  virtualisation.vfio = {
    enable = true;
    IOMMUType = "amd";       # sets amd_iommu=on
    ignoreMSRs = true;       # sets kvm.ignore_msrs=1 + kvm.report_ignored_msrs=0
    devices = [];            # no passthrough on normal boot
    blacklistNvidia = lib.mkDefault false;
    disablePCIeASPM = true; # also set in zfs.nix for NVMe stability; redundant but explicit
    disableEFIfb = false;
  };

  # VFIO specialisation: layers blacklist + device binding on top of the base.
  # Select "with-vfio" in GRUB. Default boot uses the Nvidia driver normally.
  specialisation."VFIO".configuration = {
    system.nixos.tags = [ "with-vfio" ];
    virtualisation.vfio = {
      devices = [
        machineConfig.gpu.nvidia.pciId      # RTX 3090 Graphics
        machineConfig.gpu.nvidia.audioPciId # RTX 3090 Audio
      ];
      blacklistNvidia = true;
    };
  };

  boot.kernelModules = [ "kvm-amd" "vhost_vsock" ];

  # dconf is required for virt-manager to persist its settings.
  programs.dconf.enable = true;

  environment.systemPackages = with pkgs; [
    virt-manager
    podman-compose
    util-linux
  ];

  users.users.bree.extraGroups = [ "qemu-libvirtd" "libvirtd" "podman" ];
}
