# Copy the SSD's data to ocean, so a dead SSD can be rebuilt from this box.
#
# rpool is a single drive. Only snapshots taken by sanoid (snapshots.nix) are
# sent; nothing on the target is ever rolled back or deleted by syncoid, and
# sanoid prunes the copies under the "replica" policy.
#
# The parents must exist first (see the target below), with mountpoint=none and
# readonly=on so every received dataset inherits both:
#   zfs create -o mountpoint=none -o readonly=on ocean/backup/bastion
#   zfs create -p ocean/backup/bastion/rpool/safe
#
# To get a file back, mount a snapshot of the copy. Mounting the copy itself
# with mount(8) is writable despite readonly=on, and breaks later receives.
{ config, lib, pkgs, ... }:
let
  source = "rpool/safe";
  target = "ocean/backup/bastion/rpool/safe";

  # Not copied; see snapshots.nix for why.
  skipped =
    [ "${source}/microvm-runtime" "${source}/observability-clickhouse" ];
in {
  services.syncoid = {
    enable = true;
    # Clear of sanoid's run at :00, which takes about a minute.
    interval = "*-*-* *:15:00";

    # Sending only. No snapshot or destroy: we never create sync snapshots.
    localSourceAllow = [ "hold" "send" ];
    localTargetAllow = [ "create" "mount" "receive" ];

    # One job for the whole tree. The module revokes its permission on the
    # target's parent when a job ends, so parallel first runs would cut each
    # other off.
    commands."ssd-to-ocean" = {
      inherit source target;
      recursive = true;
      sendOptions = "L c"; # keep block sizes and compression as stored
      recvOptions = "u"; # don't mount
      extraArgs = [
        "--skip-parent"
        "--no-sync-snap"
        "--no-rollback"
        # A saved partial receive whose snapshot is gone can only be cleared
        # with destroy permission, and would block every dataset after it.
        "--no-resume"
        "--include-snaps=^autosnap_"
      ] ++ map (dataset: "--exclude-datasets=^${dataset}(/|$)") skipped;
      service.unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    };
  };

  services.sanoid.datasets.${target} = {
    useTemplate = [ "replica" ];
    recursive = true;
    processChildrenOnly = true;
  };

  # sanoid and syncoid can both exit 0 without a new snapshot or copy, so check
  # the copies themselves. Every dataset under the source needs a recent one,
  # which also catches a new dataset nobody snapshots.
  systemd.services.ssd-copy-freshness = {
    description = "Check that the SSD's copies on ocean are recent";
    startAt = "*-*-* 09:45:00";
    path = [ config.boot.zfs.package pkgs.gawk ];
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
    };
    script = ''
      set -euo pipefail
      max_age=$((3 * 3600))
      now=$(date +%s)
      stale=0
      checked=0

      datasets=$(zfs list -H -t filesystem,volume -o name -r ${source})
      for dataset in $datasets; do
        case "$dataset" in
          ${source} | ${
            lib.concatMapStringsSep " | " (d: "${d} | ${d}/*") skipped
          }) continue ;;
        esac
        checked=$((checked + 1))
        copy="${target}''${dataset#${source}}"

        if ! snapshots=$(zfs list -Hp -t snapshot -d 1 -o creation,name "$copy"); then
          echo "MISSING: $copy"
          stale=1
          continue
        fi
        newest=$(awk '$2 ~ /@autosnap_/ && $1 > t { t = $1 } END { print t + 0 }' <<< "$snapshots")
        if [ "$newest" -eq 0 ]; then
          echo "NO SNAPSHOTS: $copy"
          stale=1
        elif [ $((now - newest)) -gt "$max_age" ]; then
          echo "STALE: $copy, newest is $(((now - newest) / 60)) minutes old"
          stale=1
        fi
      done

      if [ "$checked" -eq 0 ]; then
        echo "no datasets found under ${source}"
        exit 1
      fi
      [ "$stale" -eq 0 ] || exit 1
      echo "all $checked copies are recent"
    '';
  };
}
