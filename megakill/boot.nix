{ pkgs, machineConfig, ... }:

{
	# Bootloader: GRUB with ZFS support, installed as removable EFI.
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

	# Hardware-level kernel command line. ZFS ARC tuning lives in zfs.nix.
	boot.kernelParams = [
		"nvme_core.default_ps_max_latency_us=0" # Disable NVMe APST to prevent Samsung 990 PRO firmware bug causing drive disconnects
		"pcie_aspm=off" # Disable PCIe Active State Power Management as additional safeguard against NVMe drops
		"pcie_port_pm=off" # Disable PCIe port runtime power management as additional safeguard against NVMe drops
	];

	boot.initrd.systemd.enable = true;

	# Kernel modules needed for mounting LUKS devices in the initrd stage.
	boot.initrd.availableKernelModules = [ "aesni_intel" "cryptd" ];

	# cryptkey is a small LUKS device unlocked by passphrase; its decrypted
	# payload is consumed as a raw key (keyFile) by cryptswap and the ZFS pools.
	boot.initrd.luks.devices = {
		cryptkey = {
			device = "/dev/disk/by-uuid/${machineConfig.luks.cryptkeyUuid}";
		};

		cryptswap = {
			device = "/dev/disk/by-uuid/${machineConfig.luks.cryptswapUuid}";
			keyFile = "/dev/mapper/cryptkey";
			keyFileSize = 64;
		};
	};

	# cryptsetup must be explicitly bundled into the initrd.
	# path = [ pkgs.cryptsetup ] only sets $PATH if the store path is already
	# present; boot.initrd.systemd.storePaths is what actually copies it in.
	boot.initrd.systemd.storePaths = [ pkgs.cryptsetup ];

	# Close cryptkey only after all consumers have finished reading it:
	# - cryptswap reads 64 bytes as its LUKS keyfile
	# - rpool loads its ZFS native encryption key from it (hard dependency)
	# - lake also reads its key from it, but lake is not in the critical boot
	#   path: wants= so a slow/absent lake doesn't hold up sysroot.mount
	# The zfs-import-* ordering deps reference units defined in zfs.nix.
	boot.initrd.systemd.services.close-cryptkey = {
		description = "Close cryptkey LUKS device";
		wantedBy = [ "cryptsetup.target" ];
		after = [
			"systemd-cryptsetup@cryptswap.service"
			"zfs-import-rpool.service"
			"zfs-import-lake.service"
		];
		wants = [ "zfs-import-lake.service" ];
		before = [ "sysroot.mount" ];
		path = [ pkgs.cryptsetup ];
		unitConfig.DefaultDependencies = "no";
		serviceConfig.Type = "oneshot";
		script = ''
			cryptsetup close /dev/mapper/cryptkey
		'';
	};
}
