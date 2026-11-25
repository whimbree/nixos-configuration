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

  # Root connects to bastion for replication. Pin its host key system-wide so a
  # missing or stale entry in /root/.ssh/known_hosts can't break it, as it did
  # with znapzend.
  programs.ssh.knownHosts.bastion = {
    hostNames = [ "bastion" "bastion.whimsy.ts" "100.64.0.4" ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILY7d0vUNCQsR6OIRCUG7Coqbvxu16ua1w8ID0MlvgoQ";
  };

  # Local snapshots. Retention is shared: modules/snapshot-policy.nix.
  services.sanoid = {
    enable = true;
    interval = "hourly";
    datasets = {
      "rpool/safe/home".useTemplate = [ "important" ];
      "rpool/safe/persist".useTemplate = [ "important" ];
      "rpool/safe/services".useTemplate = [ "important" ];
      "lake/data".useTemplate = [ "important" ];
    };
  };
}
