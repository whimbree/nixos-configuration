{ config, pkgs, lib, ... }: {
  boot = {
    # add ZFS and NTFS as supported filesystems
    supportedFilesystems = [ "zfs" "ntfs" "ext4" ];
    # force import pools, allows importing if not cleanly exported
    zfs.forceImportAll = true;
    zfs.requestEncryptionCredentials = [ "rpool" "ocean" "neptune" ];
    # kernelParams = [
    #   "elevator=none" # ZFS has it's own scheduler
    # ];
    # reset "/" to a clean snapshot on boot
    initrd.postResumeCommands =
      lib.mkAfter "zfs rollback -r rpool/local/root@blank";
  };
  boot.loader.systemd-boot.enable = true;

  systemd.services.zfs-mount.enable = false;

  boot.kernelParams = [
    "zfs.zfs_arc_max=34359738368" # ZFS ARC Size 32GB
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

  services.znapzend = {
    enable = true;
    autoCreation = true;

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
      # Make snapshots of ocean/media every day, keep those for 1 month,
      # keep every month's snapshot for 1 year, etc.
      plan = "1m=>1d,1y=>1m";
    };
    zetup."ocean/files" = rec {
      # Make snapshots of ocean/files every hour, keep those for 1 day,
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
    zetup."neptune/media" = rec {
      # Make snapshots of ocean/media every day, keep those for 1 month,
      # keep every month's snapshot for 1 year, etc.
      plan = "1m=>1d,1y=>1m";
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

  fileSystems."/var/log" = {
    device = "rpool/local/log";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/blockchain" = {
    device = "rpool/local/blockchain";
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

  fileSystems."/microvms/airvpn-sweden" = {
    device = "rpool/safe/microvms/airvpn-sweden";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/airvpn-usa" = {
    device = "rpool/safe/microvms/airvpn-usa";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/jellyfin" = {
    device = "rpool/safe/microvms/jellyfin";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/var/lib/microvms" = {
    device = "rpool/safe/microvm-runtime";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/97E0-36CE";
    fsType = "vfat";
    neededForBoot = true;
  };

  fileSystems."/ocean/nas/bree" = {
    device = "ocean/nas/bree";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/downloads" = {
    device = "ocean/downloads";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/media" = {
    device = "ocean/media";
    fsType = "zfs";
    neededForBoot = true;
    options = [ "nofail" ];
  };

  fileSystems."/ocean/files" = {
    device = "ocean/files";
    fsType = "zfs";
    neededForBoot = true;
    options = [ "nofail" ];
  };

  fileSystems."/neptune/media" = {
    device = "neptune/media";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/public" = {
    device = "ocean/public";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/services" = {
    device = "ocean/services";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/images" = {
    device = "ocean/images";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/overkill" = {
    device = "ocean/backup/overkill";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/duplicati" = {
    device = "ocean/backup/duplicati";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  environment.systemPackages = with pkgs; [ mergerfs ];
  fileSystems."/merged/media" = {
    fsType = "fuse.mergerfs";
    depends = [ "/ocean/media" "/neptune/media" ];
    device = "/ocean/media:/neptune/media";
    options = [
      "nofail"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"
    ];
  };

  swapDevices =
    [{ device = "/dev/disk/by-uuid/47644549-bfbf-41b1-8fd7-900d3c10480e"; }];
  boot.kernel.sysctl."vm.swappiness" = 1;
  boot.kernel.sysctl."vm.vfs_cache_pressure" = 50;
  # https://askubuntu.com/questions/41778/computer-freezing-on-almost-full-ram-possibly-disk-cache-problem/922946#922946
  boot.kernel.sysctl."vm.min_free_kbytes" = 131072;

  systemd.services.zswap = {
    description = "Enable zswap";
    enable = true;
    wantedBy = [ "basic.target" ];
    path = [ pkgs.bash ];
    serviceConfig = {
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c 'cd /sys/module/zswap/parameters&& \
            echo Y > enabled&& \
            echo 25 > max_pool_percent&& \
            echo zstd > compressor&& \
            echo zsmalloc > zpool'
      '';
      Type = "simple";
    };
  };
}
