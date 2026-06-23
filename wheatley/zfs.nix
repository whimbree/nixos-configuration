{ config, pkgs, lib, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];

  # ZFS needs the hostId to be set.
  networking.hostId = "52d2d80c";

  # ensure that rpool is imported at boot
  boot.zfs.devNodes =
    "/dev/disk/by-partuuid/98ec7600-341b-4578-b97c-f4e07b6fae95";
  boot.zfs.forceImportAll = true;

  # ZFS ARC tuning. Bootloader/LUKS/initrd-network kernel params live in boot.nix.
  boot.kernelParams = [
    "zfs.zfs_arc_min=268435456" # ZFS Min ARC Size 256MB
    "zfs.zfs_arc_max=268435456" # ZFS Max ARC Size 256MB
    "elevator=none" # ZFS has it's own scheduler
  ];

  # rpool's ZFS key is read from /dev/mapper/cryptkey (opened in boot.nix), but
  # NixOS doesn't generate that dependency automatically. Without this, import
  # races against cryptkey opening and fails on first attempt.
  boot.initrd.systemd.services.zfs-import-rpool = {
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

  # ZFS already has its own scheduler. Without this computer freezes for a second under heavy load.
  services.udev.extraRules = lib.optionalString (config.boot.zfs.enabled) ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  '';
}
