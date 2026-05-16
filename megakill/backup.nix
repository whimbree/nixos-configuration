{ ... }: {

  services.zfs = {
    # Monthly scrub: reads every block and verifies checksums, correcting
    # silent corruption using redundancy. Low frequency is fine — scrubs are
    # I/O intensive and the ZFS write pipeline catches most errors on the fly.
    autoScrub = {
      enable = true;
      pools = [ "rpool" "lake" ];
      interval = "monthly";
    };
  };

  services.znapzend = {
    enable = true;
    autoCreation = true; # create destination datasets if they don't exist
    pure = true;         # znapzend manages ALL snapshots; don't touch manually
    features.sendRaw = true; # send encrypted datasets without decrypting first

    # rpool/safe/home: user home directory.
    # Hourly snapshots, kept for 1 day → daily kept for 1 month → monthly kept for 1 year.
    # Replicated to bastion via SSH as root@bastion (bastion's authorized_keys
    # already has megakill's root SSH key for this purpose).
    zetup."rpool/safe/home" = {
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        host = "bree@bastion";
        dataset = "ocean/backup/megakill/rpool/safe/home";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };

    # rpool/safe/persist: the /persist dataset holding system state.
    zetup."rpool/safe/persist" = {
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        host = "bree@bastion";
        dataset = "ocean/backup/megakill/rpool/safe/persist";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };

    # lake/data: large data pool. Snapshot locally only — too large to replicate.
    zetup."lake/data" = {
      plan = "1d=>1h,1m=>1d,1y=>1m";
    };
  };
}
