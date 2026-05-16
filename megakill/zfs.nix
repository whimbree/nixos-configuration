{ config, pkgs, lib, ... }:

{
	boot.supportedFilesystems = [ "zfs" ];
	# Kernel modules needed for mounting LUKS devices in initrd stage
	boot.initrd.availableKernelModules = [ "aesni_intel" "cryptd" ];
	boot.initrd.systemd.enable = true;

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

	# cryptsetup must be explicitly bundled into the initrd.
	# path = [ pkgs.cryptsetup ] only sets $PATH if the store path is already
	# present; boot.initrd.systemd.storePaths is what actually copies it in.
	boot.initrd.systemd.storePaths = [ pkgs.cryptsetup ];

	# Both ZFS pool imports read the encryption key from /dev/mapper/cryptkey,
	# but NixOS doesn't generate that dependency automatically. Without this,
	# both services race against cryptkey opening and fail on first attempt.
	boot.initrd.systemd.services.zfs-import-rpool = {
		after = [ "systemd-cryptsetup@cryptkey.service" ];
		requires = [ "systemd-cryptsetup@cryptkey.service" ];
	};
	boot.initrd.systemd.services.zfs-import-lake = {
		after = [ "systemd-cryptsetup@cryptkey.service" ];
		requires = [ "systemd-cryptsetup@cryptkey.service" ];
	};

	# Close cryptkey only after all consumers have finished reading it:
	# - cryptswap reads 64 bytes as its LUKS keyfile
	# - rpool loads its ZFS native encryption key from it (hard dependency)
	# - lake also reads its key from it, but lake is not in the critical boot
	#   path: wants= so a slow/absent lake doesn't hold up sysroot.mount
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

	# Roll back the ephemeral root to the blank snapshot on every boot.
	boot.initrd.systemd.services.rollback = {
		description = "Rollback ZFS root to blank snapshot";
		wantedBy = [ "initrd.target" ];
		after = [ "zfs-import-rpool.service" ];
		before = [ "sysroot.mount" ];
		path = [ pkgs.zfs ];
		unitConfig.DefaultDependencies = "no";
		serviceConfig.Type = "oneshot";
		script = ''
			zfs rollback -r rpool/local/root@blank
		'';
	};

	systemd.services.zfs-mount.enable = false;

	networking.hostId = "0efa0ed8";
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

	boot.zfs.forceImportRoot = true; # single machine, always safe to force import after unclean shutdown
	boot.zfs.forceImportAll = true;
	boot.zfs.requestEncryptionCredentials = [ "rpool" "lake" ];
}
