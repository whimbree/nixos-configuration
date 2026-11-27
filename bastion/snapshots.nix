# Local snapshots. Replication to megakill is separate and builds on these.
#
# Deliberately not snapshotted: rpool/safe/microvm-runtime (replaceable VM
# state), rpool/safe/observability-clickhouse and ocean/backup/observability
# (see docs/observability-zfs-provisioning.md), ocean/downloads.
{ ... }: {
  services.sanoid = {
    enable = true;
    interval = "hourly";

    # recursive = "zfs" snapshots a whole tree atomically, so a service's
    # database and its parent directory are captured at the same instant.
    datasets = {
      "ocean/services" = {
        useTemplate = [ "important" ];
        recursive = "zfs";
      };
      "rpool/safe/services" = {
        useTemplate = [ "important" ];
        recursive = "zfs";
      };
      "rpool/safe/microvms" = {
        useTemplate = [ "important" ];
        recursive = "zfs";
      };
      # Recursive because the data is in ocean/nas/bree, not here.
      "ocean/nas" = {
        useTemplate = [ "important" ];
        recursive = "zfs";
      };
      "rpool/safe/home".useTemplate = [ "important" ];
      "rpool/safe/persist".useTemplate = [ "important" ];
      "ocean/files".useTemplate = [ "important" ];
      "ocean/public".useTemplate = [ "important" ];
      "ocean/backup/duplicati".useTemplate = [ "important" ];

      "ocean/images".useTemplate = [ "media" ];
      "ocean/media".useTemplate = [ "media" ];
      "neptune/media".useTemplate = [ "media" ];
    };
  };
}
