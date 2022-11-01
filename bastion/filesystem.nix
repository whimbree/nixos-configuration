{ config, pkgs, lib, ... }: {
  boot = {
    # add ZFS as a supported filesystem
    supportedFilesystems = [ "zfs" ];
    # force import pools, allows importing if not cleanly exported
    zfs.forceImportAll = true;
    # ensure that packages used are compatible with ZFS
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
    # reset "/" to a clean snapshot on boot
    initrd.postDeviceCommands =
      lib.mkAfter "zfs rollback -r rpool/local/root@blank";
  };

  # setup GRUB in UEFI mode only
  boot.loader = {
    efi.efiSysMountPoint = "/boot/efi";
    generationsDir.copyKernels = true;
    grub = {
      enable = true;
      version = 2;
      efiInstallAsRemovable = true;
      copyKernels = true;
      efiSupport = true;
      zfsSupport = true;
      device = "nodev";
    };
  };

  # ZFS needs the hostId to be set
  networking.hostId = "f00d1337";

  services.zfs = {
    # enable automatic scrubbing
    autoScrub.enable = true;
    # enable automatic snapshots
    autoSnapshot = {
      enable = true;
      frequent = 0;
      hourly = 0;
      daily = 7;
      weekly = 1;
      monthly = 0;
    };
  };

  fileSystems."/" = {
    device = "rpool/local/root";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/nix" = {
    device = "rpool/local/nix";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "rpool/safe/home";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/persist" = {
    device = "rpool/safe/persist";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "bpool/root";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-uuid/711E-FDDA";
    fsType = "vfat";
    neededForBoot = true;
  };

  fileSystems."/ocean/nas/bree" = {
    device = "ocean/nas/bree";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/media" = {
    device = "ocean/media";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/public" = {
    device = "ocean/public";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/megakill" = {
    device = "ocean/backup/megakill";
    fsType = "zfs";
    neededForBoot = true;
  };

  swapDevices =
    [{ device = "/dev/disk/by-uuid/5f7b24b8-d028-4896-a6a3-62c83edd1b22"; }];

}
