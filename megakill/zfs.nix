{ pkgs, machineConfig, ... }:

{
	boot.supportedFilesystems = [ "zfs" ];

	networking.hostId = machineConfig.hostId;

	# ZFS ARC tuning. Bootloader and hardware kernel params live in boot.nix.
	boot.kernelParams = [
		"zfs.zfs_arc_min=4294967296"  # ZFS Min ARC Size 4 GB
		"zfs.zfs_arc_max=34359738368" # ZFS Max ARC Size 32 GB
	];

	# Both ZFS pool imports read the encryption key from /dev/mapper/cryptkey
	# (opened in boot.nix), but NixOS doesn't generate that dependency
	# automatically. Without this, both services race against cryptkey opening
	# and fail on first attempt.
	boot.initrd.systemd.services.zfs-import-rpool = {
		after = [ "systemd-cryptsetup@cryptkey.service" ];
		requires = [ "systemd-cryptsetup@cryptkey.service" ];
	};
	boot.initrd.systemd.services.zfs-import-lake = {
		after = [ "systemd-cryptsetup@cryptkey.service" ];
		requires = [ "systemd-cryptsetup@cryptkey.service" ];
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

	boot.zfs.forceImportRoot = true; # single machine, always safe to force import after unclean shutdown
	boot.zfs.forceImportAll = true;
	boot.zfs.requestEncryptionCredentials = [ "rpool" "lake" ];
}
