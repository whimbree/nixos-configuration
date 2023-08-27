{ config, pkgs, lib, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  # Kernel modules needed for mounting LUKS devices in initrd stage
  boot.initrd.availableKernelModules = [ "aesni_intel" "cryptd" ];

  boot.initrd.luks.devices = {
    cryptkey = {
      device = "/dev/disk/by-uuid/3e517661-c696-4c31-ae87-810024e1d273";
    };

    cryptswap = {
      device = "/dev/disk/by-uuid/383313f3-61e9-42cd-b946-f0ac0596aaad";
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
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  boot.initrd.postDeviceCommands =
    lib.mkAfter "	zfs rollback -r rpool/local/root@blank\n";

  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.generationsDir.copyKernels = true;
  boot.loader.grub = {
    enable = true;
    efiInstallAsRemovable = true;
    copyKernels = true;
    efiSupport = true;
    zfsSupport = true;
    device = "nodev";
    default = "saved";
  };

  # ZFS ARC Size 8GB
  boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];

  boot.zfs.forceImportAll = true;

  # ZFS already has its own scheduler. Without this computer freezes for a second under heavy load.
  services.udev.extraRules = lib.optionalString (config.boot.zfs.enabled) ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  '';
}
