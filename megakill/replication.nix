# Second copies of bastion's important data on lake, pulled over Tailscale:
# its SSD (rpool/safe, which holds the Immich and Nextcloud databases) and
# the important datasets on ocean (Immich and Nextcloud files, the NAS share).
# The first copies are on bastion's ocean (bastion/replication.nix).
#
# bastion's key for us can only list and send those datasets
# (homelab.syncoidSend in bastion/replication.nix). Only sanoid's snapshots
# are copied; nothing on lake is ever rolled back or deleted by syncoid, and
# sanoid prunes the copies under the "replica" policy.
#
# The targets must exist first, inheriting mountpoint=none and readonly=on:
#   zfs set readonly=on lake/backup/bastion          # mountpoint is none
#   zfs create -p lake/backup/bastion/rpool/safe
#   zfs create -p lake/backup/bastion/ocean/backup   # parent for duplicati
#
# To get a file back, mount a snapshot of the copy, e.g.
#   mount -t zfs lake/backup/bastion/ocean/nas/bree@<snap> /mnt
# Mounting the copy itself with mount(8) is writable despite readonly=on, and
# breaks later receives.
{ config, lib, pkgs, ... }:
let
  bastion = "syncoid-send@100.64.0.4";

  ssd = {
    source = "rpool/safe";
    target = "lake/backup/bastion/rpool/safe";
    # Not snapshotted on bastion; see bastion/snapshots.nix.
    skipped = [ "rpool/safe/microvm-runtime" "rpool/safe/observability-clickhouse" ];
  };

  ocean = {
    source = "ocean";
    target = "lake/backup/bastion/ocean";
    # Copied with their children. Must match homelab.syncoidSend.datasets in
    # bastion/replication.nix. Not copied: media, images, downloads, and the
    # other hosts' backups kept on ocean.
    datasets = [ "services" "nas" "files" "public" "backup/duplicati" ];
  };

  # Kept in /persist so it survives the root rollback. Created once by hand:
  #   sudo install -d -m 700 /persist/var/lib/syncoid
  #   sudo ssh-keygen -t ed25519 -N "" -C syncoid@megakill \
  #     -f /persist/var/lib/syncoid/bastion_ed25519
  # and its .pub goes in bastion/replication.nix.
  home = "/persist/var/lib/syncoid";
  key = "${home}/bastion_ed25519";

  commonArgs = [
    "--no-sync-snap"
    "--no-rollback"
    # A saved partial receive whose snapshot is gone can only be cleared with
    # destroy permission, and would block every dataset after it.
    "--no-resume"
    "--include-snaps=^autosnap_"
    # bastion's filter allows no compressor or buffer in the remote command.
    "--compress=none"
  ];
in {
  services.syncoid = {
    enable = true;
    # After bastion's sanoid at :00 and its own copy to ocean at :15.
    interval = "*-*-* *:20:00";
    localTargetAllow = [ "create" "mount" "receive" ];

    # The two jobs may overlap: their targets already exist, so each job's
    # temporary permission is on its own target, not a shared parent.
    commands."bastion-ssd-to-lake" = {
      source = "${bastion}:${ssd.source}";
      inherit (ssd) target;
      recursive = true;
      sshKey = key;
      sendOptions = "L c"; # keep block sizes and compression as stored
      recvOptions = "u"; # don't mount
      extraArgs = commonArgs ++ [ "--skip-parent" ]
        ++ map (dataset: "--exclude-datasets=^${dataset}(/|$)") ssd.skipped;
      service.unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    };

    commands."bastion-ocean-to-lake" = {
      source = "${bastion}:${ocean.source}";
      inherit (ocean) target;
      recursive = true;
      sshKey = key;
      sendOptions = "L c";
      recvOptions = "u";
      # Everything under ocean except the listed datasets and their children.
      # ocean/backup itself is excluded too; its copy is the empty dataset
      # created above.
      extraArgs = commonArgs ++ [
        "--skip-parent"
        "--exclude-datasets=^ocean/(?!(${lib.concatStringsSep "|" ocean.datasets})(/|$))"
      ];
      service.unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    };
  };
  systemd.timers.syncoid-bastion-ocean-to-lake.timerConfig.OnCalendar =
    lib.mkForce "*-*-* *:40:00";

  users.users.syncoid.home = lib.mkForce home;
  # Z: the key may have been made by root before syncoid's account existed.
  systemd.tmpfiles.rules = [
    "d ${home} 0700 syncoid syncoid -"
    "Z ${home} - syncoid syncoid -"
  ];

  services.sanoid.datasets = lib.genAttrs [ ssd.target ocean.target ] (_: {
    useTemplate = [ "replica" ];
    recursive = true;
    processChildrenOnly = true;
  });
  # sanoid runs `zfs allow` before and `zfs unallow` after every run, and each
  # waits for a transaction group to sync. While a big receive is writing to
  # lake, that takes minutes, past the default 90s stop timeout, so the run
  # was killed and reported as failed although its snapshots were fine.
  systemd.services.sanoid.serviceConfig.TimeoutSec = "15min";

  # sanoid and syncoid can both exit 0 without a new snapshot or copy, so
  # check the copies themselves against what bastion has now, which also
  # catches a new dataset on bastion that nobody snapshots.
  systemd.services.copy-freshness = {
    description = "Check that the copies of bastion on lake are recent";
    startAt = "*-*-* 10:15:00";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ config.boot.zfs.package pkgs.gawk pkgs.openssh ];
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "syncoid"; # for the key
    };
    script = ''
      set -euo pipefail
      max_age=$((3 * 3600))
      now=$(date +%s)
      stale=0
      checked=0

      on_bastion() {
        ssh -i ${key} -o IdentitiesOnly=yes -o BatchMode=yes ${bastion} "$*"
      }

      check() {
        local copy=$1 snapshots newest
        checked=$((checked + 1))
        if ! snapshots=$(zfs list -Hp -t snapshot -d 1 -o creation,name "$copy"); then
          echo "MISSING: $copy"
          stale=1
          return
        fi
        newest=$(awk '$2 ~ /@autosnap_/ && $1 > t { t = $1 } END { print t + 0 }' <<< "$snapshots")
        if [ "$newest" -eq 0 ]; then
          echo "NO SNAPSHOTS: $copy"
          stale=1
        elif [ $((now - newest)) -gt "$max_age" ]; then
          echo "STALE: $copy, newest is $(((now - newest) / 60)) minutes old"
          stale=1
        fi
      }

      ssd=$(on_bastion zfs list -H -t filesystem,volume -o name -r ${ssd.source})
      [ -n "$ssd" ] || { echo "no datasets found under ${ssd.source} on bastion"; exit 1; }
      for dataset in $ssd; do
        case "$dataset" in
          ${ssd.source} | ${
            lib.concatMapStringsSep " | " (d: "${d} | ${d}/*") ssd.skipped
          }) continue ;;
        esac
        check "${ssd.target}''${dataset#${ssd.source}}"
      done

      for root in ${lib.concatMapStringsSep " " (d: "${ocean.source}/${d}") ocean.datasets}; do
        datasets=$(on_bastion zfs list -H -t filesystem,volume -o name -r "$root")
        [ -n "$datasets" ] || { echo "no datasets found under $root on bastion"; exit 1; }
        for dataset in $datasets; do
          check "${ocean.target}''${dataset#${ocean.source}}"
        done
      done

      [ "$stale" -eq 0 ] || exit 1
      echo "all $checked copies are recent"
    '';
  };
}
