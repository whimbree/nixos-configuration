{ config, pkgs, lib, ... }: {

  services.zfs = {
    # enable automatic scrubbing
    autoScrub = {
      enable = true;
      pools = [ "rpool" ];
      interval = "Mon, 02:00";
    };
  };

  # Local snapshots. Retention is shared: modules/snapshot-policy.nix.
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets = {
      "rpool/safe/home".useTemplate = [ "important" ];
      "rpool/safe/persist".useTemplate = [ "important" ];
      "rpool/safe/services".useTemplate = [ "important" ];
    };
  };
}
