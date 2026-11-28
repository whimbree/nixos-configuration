{ ... }: {
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

  # bastion pulls copies of rpool/safe/* (bastion/replication.nix) with a
  # send-only key; see modules/syncoid-send.nix.
  homelab.syncoidSend = {
    enable = true;
    datasets = [ "rpool/safe" ];
    # Private half: bastion:/persist/var/lib/syncoid/wheatley_ed25519.
    clients.bastion = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKZPIWWqQmirTyq4oKMOEbwJ+MI2zQ/E3gob6EkGbmfC syncoid@bastion";
      address = "100.64.0.4";
    };
  };
}
