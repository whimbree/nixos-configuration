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
  };

  boot.zfs.forceImportAll = true;
}
