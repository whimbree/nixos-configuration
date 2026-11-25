{ config, pkgs, lib, ... }: {

  services.zfs = {
    # enable automatic scrubbing
    autoScrub = {
      enable = true;
      pools = [ "rpool" ];
      interval = "Mon, 02:00";
    };
  };

  # Local snapshots, beside znapzend until the new replication has passed a
  # restore test. Retention is shared: modules/snapshot-policy.nix.
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets = {
      "rpool/safe/home".useTemplate = [ "important" ];
      "rpool/safe/persist".useTemplate = [ "important" ];
      "rpool/safe/services".useTemplate = [ "important" ];
    };
  };

  services.znapzend = {
    enable = true;
    autoCreation = true;
    pure = true;
    features.sendRaw = true;

    zetup."rpool/safe/home" = rec {
      # Make snapshots of rpool/safe/home every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        host = "bree@bastion";
        dataset = "ocean/backup/wheatley/rpool/safe/home";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
    zetup."rpool/safe/services" = rec {
      # Make snapshots of rpool/safe/home every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        host = "bree@bastion";
        dataset = "ocean/backup/wheatley/rpool/safe/services";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
    zetup."rpool/safe/persist" = rec {
      # Make snapshots of rpool/safe/persist every hour, keep those for 1 day,
      # keep every days snapshot for 1 month, etc.
      plan = "1d=>1h,1m=>1d,1y=>1m";
      destinations.backup = {
        host = "bree@bastion";
        dataset = "ocean/backup/wheatley/rpool/safe/persist";
        plan = "1d=>1h,1m=>1d,1y=>1m";
      };
    };
  };
}
