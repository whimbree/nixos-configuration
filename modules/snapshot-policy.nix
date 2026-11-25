# Shared snapshot retention, so a dataset means the same thing on every host.
# Templates do nothing until a host enables services.sanoid and uses them.
#
# sanoid only takes and prunes snapshots named autosnap_*. It reads every
# snapshot on the system each run, so keep the total in the low thousands.
{ ... }: {
  services.sanoid.templates = {
    # Data we'd want back: undo a mistake by the hour, and look back 6 months.
    important = {
      hourly = 48;
      daily = 30;
      monthly = 6;
      yearly = 0;
      autosnap = true;
      autoprune = true;
    };

    # Replaceable bulk data. Short, because deleted media keeps using space for
    # as long as a snapshot references it.
    media = {
      hourly = 0;
      daily = 14;
      monthly = 2;
      yearly = 0;
      autosnap = true;
      autoprune = true;
    };

    # Copies on another pool or machine. Pruned here, never snapshotted here.
    replica = {
      hourly = 48;
      daily = 90;
      monthly = 24;
      yearly = 0;
      autosnap = false;
      autoprune = true;
    };
  };
}
