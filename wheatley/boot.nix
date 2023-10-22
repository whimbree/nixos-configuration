{ config, pkgs, lib, ... }:

{
  boot.loader.grub = {
    enable = true;
    copyKernels = true;
    zfsSupport = true;
    device = "/dev/vda";
  };

  # Kernel modules needed for mounting LUKS devices in initrd stage
  boot.initrd.availableKernelModules = [ "aesni_intel" "cryptd" ];

  boot.initrd.luks.devices = {
    cryptkey = {
      device = "/dev/disk/by-uuid/8cac0f80-8059-47db-b131-f79622453527";
    };

    cryptswap = {
      device = "/dev/disk/by-uuid/ab7ea64b-ee73-4f72-a103-ffd33521a5c2";
      keyFile = "/dev/mapper/cryptkey";
      keyFileSize = 64;
    };
  };

  # ensure that rpool is imported at boot
  boot.zfs.devNodes =
    "/dev/disk/by-partuuid/98ec7600-341b-4578-b97c-f4e07b6fae95";
  boot.zfs.forceImportAll = true;

  # close cryptkey at end of initrd boot stage
  boot.initrd.postMountCommands = "cryptsetup close /dev/mapper/cryptkey";

  # reset / on every boot
  boot.initrd.postDeviceCommands =
    lib.mkAfter "	zfs rollback -r rpool/local/root@blank\n";

  # ZFS configuration
  networking.hostId = "52d2d80c";
  boot.supportedFilesystems = [ "zfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  boot.kernelParams = [
    "zfs.zfs_arc_min=67108864" # ZFS ARC Size 64MB
    "zfs.zfs_arc_max=67108864" # ZFS ARC Size 64MB
    "elevator=none" # ZFS has it's own scheduler
  ];

  # ZFS already has its own scheduler. Without this computer freezes for a second under heavy load.
  services.udev.extraRules = lib.optionalString (config.boot.zfs.enabled) ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  '';

  # enable LUKS unlock over SSH
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
      ];
      hostKeys =
        [ "/etc/ssh/ssh_host_ed25519_key" "/etc/ssh/ssh_host_rsa_key" ];
    };
  };
  # copy SSH keys into initrd
  boot.initrd.secrets = {
    "/etc/ssh/ssh_host_ed25519_key" = lib.mkForce "/etc/ssh/ssh_host_ed25519_key";
    "/etc/ssh/ssh_host_rsa_key" = lib.mkForce "/etc/ssh/ssh_host_rsa_key";
  };

}
