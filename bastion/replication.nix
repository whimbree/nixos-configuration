# Copies kept on ocean: this box's SSD, so a dead SSD can be rebuilt from here,
# and wheatley, which keeps no copy of its own.
#
# Only snapshots taken by sanoid are sent; nothing on a target is ever rolled
# back or deleted by syncoid, and sanoid prunes the copies under the "replica"
# policy.
#
# The parents must exist first, with mountpoint=none and readonly=on so every
# received dataset inherits both:
#   zfs create -o mountpoint=none -o readonly=on ocean/backup/<host>
#   zfs create -p ocean/backup/<host>/rpool/safe
#
# To get a file back, mount a snapshot of the copy. Mounting the copy itself
# with mount(8) is writable despite readonly=on, and breaks later receives.
{ config, lib, pkgs, ... }:
let
  ssd = {
    source = "rpool/safe";
    target = "ocean/backup/bastion/rpool/safe";
    # Not copied; see snapshots.nix for why.
    skipped = [ "rpool/safe/microvm-runtime" "rpool/safe/observability-clickhouse" ];
  };

  wheatley = {
    # By Tailscale IPv4 address: wheatley only accepts the key from bastion's
    # IPv4 address, and the name also resolves to IPv6.
    source = "syncoid-send@100.64.0.3:rpool/safe";
    target = "ocean/backup/wheatley/rpool/safe";
    datasets = [ "home" "persist" "services" ];
  };

  # Kept in /persist so it survives the root rollback. Created once by hand:
  #   sudo -u syncoid ssh-keygen -t ed25519 -N "" -C syncoid@bastion \
  #     -f /persist/var/lib/syncoid/wheatley_ed25519
  # and its .pub goes in wheatley/backup.nix.
  home = "/persist/var/lib/syncoid";

  commonArgs = [
    "--skip-parent"
    "--no-sync-snap"
    "--no-rollback"
    # A saved partial receive whose snapshot is gone can only be cleared with
    # destroy permission, and would block every dataset after it.
    "--no-resume"
    "--include-snaps=^autosnap_"
  ];
in {
  services.syncoid = {
    enable = true;
    # Clear of sanoid's run at :00, which takes about a minute.
    interval = "*-*-* *:15:00";

    # Sending only. No snapshot or destroy: we never create sync snapshots.
    localSourceAllow = [ "hold" "send" ];
    localTargetAllow = [ "create" "mount" "receive" ];

    # One job per tree. The module revokes its permission on the target's
    # parent when a job ends, so parallel first runs would cut each other off.
    commands."ssd-to-ocean" = {
      inherit (ssd) source target;
      recursive = true;
      sendOptions = "L c"; # keep block sizes and compression as stored
      recvOptions = "u"; # don't mount
      extraArgs = commonArgs
        ++ map (dataset: "--exclude-datasets=^${dataset}(/|$)") ssd.skipped;
      service.unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    };

    # Pulled: wheatley's key (wheatley/backup.nix) can only list and send.
    commands."wheatley-to-ocean" = {
      inherit (wheatley) source target;
      recursive = true;
      sshKey = "${home}/wheatley_ed25519";
      sendOptions = "L c";
      recvOptions = "u";
      # Its filter allows no compressor or buffer in the remote command.
      extraArgs = commonArgs ++ [ "--compress=none" ];
      service.unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    };
  };
  # Not at the same time as the SSD copy.
  systemd.timers.syncoid-wheatley-to-ocean.timerConfig.OnCalendar =
    lib.mkForce "*-*-* *:30:00";

  users.users.syncoid.home = lib.mkForce home;
  systemd.tmpfiles.rules = [ "d ${home} 0700 syncoid syncoid -" ];

  # megakill pulls second copies of these to its lake pool
  # (megakill/replication.nix), with a key that can only list and send them.
  # Keep in step with the datasets listed there.
  homelab.syncoidSend = {
    enable = true;
    datasets = [
      ssd.source
      "ocean/services"
      "ocean/nas"
      "ocean/files"
      "ocean/public"
      "ocean/backup/duplicati"
    ];
    # Private half: megakill:/persist/var/lib/syncoid/bastion_ed25519.
    clients.megakill = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFtRtdjFIaLRRTQRlWFDpEvvdgbVh+xLjJnHELVcGMM5 syncoid@megakill";
      address = "100.64.0.10";
    };
  };

  programs.ssh.knownHosts.wheatley = {
    hostNames = [ "wheatley" "wheatley.whimsy.ts" "100.64.0.3" ];
    publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJiWe9KUzjAK7beHEMySLnUcZw7gKDUgA3vRHp7Y098a";
  };

  services.sanoid.datasets = lib.genAttrs [ ssd.target wheatley.target ] (_: {
    useTemplate = [ "replica" ];
    recursive = true;
    processChildrenOnly = true;
  });

  # sanoid and syncoid can both exit 0 without a new snapshot or copy, so check
  # the copies themselves. Every dataset under the SSD's tree needs a recent
  # copy, which also catches a new dataset nobody snapshots.
  systemd.services.copy-freshness = {
    description = "Check that the copies on ocean are recent";
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

      ssd=$(zfs list -H -t filesystem,volume -o name -r ${ssd.source})
      [ -n "$ssd" ] || { echo "no datasets found under ${ssd.source}"; exit 1; }
      for dataset in $ssd; do
        case "$dataset" in
          ${ssd.source} | ${
            lib.concatMapStringsSep " | " (d: "${d} | ${d}/*") ssd.skipped
          }) continue ;;
        esac
        check "${ssd.target}''${dataset#${ssd.source}}"
      done

      for dataset in ${lib.concatStringsSep " " wheatley.datasets}; do
        check "${wheatley.target}/$dataset"
      done

      [ "$stale" -eq 0 ] || exit 1
      echo "all $checked copies are recent"
    '';
  };
}
