{ config, pkgs, lib, ... }: {
  boot = {
    # add ZFS and NTFS as supported filesystems
    supportedFilesystems = [ "zfs" "ntfs" ];
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
    autoScrub = {
      enable = true;
      pools = [ "bpool" "rpool" "ocean" ];
      interval = "Mon, 02:00";
    };
  };

  services.znapzend = {
    enable = true;
    autoCreation = true;

    zetup."bpool/root" = rec {
      # Make snapshots of bpool/root every week, keep those for 1 month, etc.
      plan = "1m=>1w,1y=>1m";
      destinations.backup = {
        dataset = "ocean/backup/bastion/bpool/root";
        plan = "1m=>1w,1y=>1m";
      };
    };

    zetup."rpool/safe/home" = rec {
      # Make snapshots of rpool/safe/home every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        dataset = "ocean/backup/bastion/rpool/safe/home";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
    zetup."rpool/safe/libvirt" = rec {
      # Make snapshots of rpool/safe/libvirt every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        dataset = "ocean/backup/bastion/rpool/safe/libvirt";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
    zetup."rpool/safe/lxd" = rec {
      # Make snapshots of rpool/safe/lxd every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      recursive = true;
      destinations.backup = {
        dataset = "ocean/backup/bastion/rpool/safe/lxd";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
    zetup."rpool/safe/persist" = rec {
      # Make snapshots of rpool/safe/persist every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        dataset = "ocean/backup/bastion/rpool/safe/persist";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
    zetup."rpool/safe/services" = rec {
      # Make snapshots of rpool/safe/services every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        dataset = "ocean/backup/bastion/rpool/safe/services";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };

    zetup."ocean/backup/megakill" = rec {
      # Make snapshots of ocean/backup/megakill every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/backup/overkill" = rec {
      # Make snapshots of ocean/backup/overkill every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/backup/duplicati" = rec {
      # Make snapshots of ocean/backup/duplicati every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/images" = rec {
      # Make snapshots of ocean/images every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/media" = rec {
      # Make snapshots of ocean/media every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/nas" = rec {
      # Make snapshots of ocean/nas every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/services" = rec {
      # Make snapshots of ocean/services every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
    zetup."ocean/public" = rec {
      # Make snapshots of ocean/public every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
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

  fileSystems."/var/lib/docker" = {
    device = "rpool/local/docker";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/var/lib/libvirt" = {
    device = "rpool/safe/libvirt";
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

  fileSystems."/services" = {
    device = "rpool/safe/services";
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

  fileSystems."/ocean/downloads" = {
    device = "ocean/downloads";
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

  fileSystems."/ocean/services" = {
    device = "ocean/services";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/images" = {
    device = "ocean/images";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/megakill" = {
    device = "ocean/backup/megakill";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/overkill" = {
    device = "ocean/backup/overkill";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/duplicati" = {
    device = "ocean/backup/duplicati";
    fsType = "zfs";
    neededForBoot = true;
  };

  swapDevices =
    [{ device = "/dev/disk/by-uuid/5f7b24b8-d028-4896-a6a3-62c83edd1b22"; }];
}
