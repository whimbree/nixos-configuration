{ config, lib, ... }: {
  boot = {
    # add ZFS and NTFS as supported filesystems
    supportedFilesystems = [ "zfs" "ntfs" "ext4" ];
    # force import pools, allows importing if not cleanly exported
    zfs.forceImportAll = true;
    zfs.requestEncryptionCredentials = [ "rpool" "ocean" "neptune" ];
    # reset "/" to a clean snapshot on boot
    initrd.postResumeCommands =
      lib.mkAfter "zfs rollback -r rpool/local/root@blank";
  };

  systemd.services.zfs-mount.enable = false;

  # ZFS ARC tuning. Bootloader/LUKS/hardware kernel params live in boot.nix.
  boot.kernelParams = [
    "zfs.zfs_arc_min=4294967296" # ZFS Min ARC Size 4GB
    "zfs.zfs_arc_max=17179869184" # ZFS Max ARC Size 16GB
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
      recursive = true;
    };

    zetup."rpool/safe/microvms" = rec {
      # Make snapshots of rpool/safe/services every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        dataset = "ocean/backup/bastion/rpool/safe/microvms";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
      recursive = true;
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
      recursive = true;
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
}
