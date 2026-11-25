{ config, lib, ... }: {
  boot = {
    # add ZFS and NTFS as supported filesystems
    supportedFilesystems = [ "zfs" "ntfs" "ext4" ];
    # force import pools, allows importing if not cleanly exported
    # (forceImportAll requires forceImportRoot)
    zfs.forceImportRoot = true;
    zfs.forceImportAll = true;
    zfs.requestEncryptionCredentials = [ "rpool" "ocean" "neptune" ];
  };

  # All three pools read their ZFS key from /dev/mapper/cryptkey (opened in
  # boot.nix), but NixOS doesn't generate that dependency automatically.
  # Without this, imports race against cryptkey opening and fail on first
  # attempt.
  boot.initrd.systemd.services = lib.genAttrs
    [ "zfs-import-rpool" "zfs-import-ocean" "zfs-import-neptune" ]
    (_: {
      after = [ "systemd-cryptsetup@cryptkey.service" ];
      requires = [ "systemd-cryptsetup@cryptkey.service" ];
    }) // {
      # Roll back the ephemeral root to the blank snapshot on every boot.
      rollback = {
        description = "Rollback ZFS root to blank snapshot";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-rpool.service" ];
        before = [ "sysroot.mount" ];
        path = [ config.boot.zfs.package ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          zfs rollback -r rpool/local/root@blank
        '';
      };
    };

  systemd.services.zfs-mount.enable = false;

  # ZFS ARC tuning. Bootloader/LUKS/hardware kernel params live in boot.nix.
  boot.kernelParams = [
    "zfs.zfs_arc_min=4294967296" # ZFS Min ARC Size 4GB
    # With all 18 MicroVMs warm, ARC naturally retreated to about 12 GiB only
    # after direct reclaim. Make that the ceiling so it does not first grow to
    # 16 GiB and leave the host with only 3-4 GiB of available memory.
    "zfs.zfs_arc_max=12884901888" # ZFS Max ARC Size 12GB
  ];

  boot.extraModprobeConfig = ''
    options zfs l2arc_noprefetch=0 l2arc_headroom=4 l2arc_rebuild_enabled=1 l2arc_feed_again=1 l2arc_write_boost=33554432 l2arc_write_max=16777216
  '';

  # ZFS already has its own scheduler. Without this computer freezes for a second under heavy load.
  services.udev.extraRules = lib.optionalString (config.boot.zfs.enabled) ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  '';

  # ZFS needs the hostId to be set
  networking.hostId = "f00d1337";

  services.zfs = {
    # enable automatic scrubbing
    autoScrub = {
      enable = true;
      pools = [ "rpool" "ocean" "neptune" ];
      interval = "monthly";
    };
  };
}
