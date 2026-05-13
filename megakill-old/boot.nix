{ config, pkgs, lib, ... }:

{
  boot.supportedFilesystems = [ "zfs" "ntfs" "ext4" ];
  # Kernel modules needed for mounting LUKS devices in initrd stage
  boot.initrd.availableKernelModules = [ "aesni_intel" "cryptd" ];

  boot.initrd.systemd.enable = false;

	boot.initrd.luks.devices = {
		cryptkey = {
			device = "/dev/disk/by-uuid/cc34a9f2-34e4-4a6a-b044-16621f5c988a";
		};

		cryptswap = {
			device = "/dev/disk/by-uuid/500a8f51-2f5a-4ba7-9b25-0b3b75570b76";
			keyFile = "/dev/mapper/cryptkey";
			keyFileSize = 64;
		};
	};

  # close cryptkey at end of initrd boot stage
  boot.initrd.postMountCommands = "cryptsetup close /dev/mapper/cryptkey";

  # enable LUKS unlock over SSH
  boot.initrd.network.enable = true;
  # copy SSH key into initrd
  boot.initrd.secrets = {
    "/persist/etc/secrets/initrd/ssh_host_ed25519_key" =
      "/persist/etc/secrets/initrd/ssh_host_ed25519_key";
  };

  boot.initrd.network.ssh = {
    enable = true;
    port = 22;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
    ];
    hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
  };

  networking.hostId = "52d2d80c";

	boot.initrd.postResumeCommands =
    lib.mkAfter "zfs rollback -r rpool/local/root@blank";

	boot.loader.efi.efiSysMountPoint = "/boot/efi";
	boot.loader.generationsDir.copyKernels = true;
	boot.loader.systemd-boot.enable = false;
	boot.loader.efi.canTouchEfiVariables = false;
	boot.loader.grub.efiInstallAsRemovable = true;
	boot.loader.grub = {
		enable = true;
		copyKernels = true;
		efiSupport = true;
		zfsSupport = true;
		device = "nodev";
	};

  boot.kernelParams = [
    "zfs.zfs_arc_min=4294967296" # ZFS Min ARC Size 4GB
    "zfs.zfs_arc_max=34359738368" # ZFS Max ARC Size 32GB
    "nvme_core.default_ps_max_latency_us=0" # Disable NVMe APST to prevent Samsung 990 PRO firmware bug causing drive disconnects
    "pcie_aspm=off" # Disable PCIe Active State Power Management as additional safeguard against NVMe drops
    "pcie_port_pm=off" # Disable PCIe port runtime power management as additional safeguard against NVMe drops
    # "elevator=none" # ZFS has it's own scheduler
  ];

  boot.zfs.forceImportAll = true;
  boot.zfs.requestEncryptionCredentials = [ "rpool" "lake" ];

  # ZFS already has its own scheduler. Without this computer freezes for a second under heavy load.
  services.udev.extraRules = lib.optionalString (config.boot.zfs.enabled) ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  '';
}
