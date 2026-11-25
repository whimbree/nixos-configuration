# What a bare-metal restore needs that replication doesn't carry: partition
# layout and UUIDs, pool settings, dataset properties and the dataset list.
#
# Written to /persist, so it is snapshotted and copied to ocean with the rest of
# the SSD. Contains no key material.
{ config, pkgs, ... }: {
  systemd.services.recovery-notes = {
    description = "Record disk and ZFS layout for bare-metal recovery";
    startAt = "*-*-* 23:30:00";
    path = [ config.boot.zfs.package pkgs.util-linux pkgs.gawk ];
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail
      umask 077
      out=/persist/recovery
      tmp=$out.tmp
      rm -rf "$tmp"
      mkdir -p "$tmp"
      cd "$tmp"

      {
        date -Is
        readlink -f /run/current-system
      } > system.txt

      lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTLABEL,PARTUUID,MODEL,SERIAL > lsblk.txt
      blkid > blkid.txt
      for disk in $(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }'); do
        case "$disk" in /dev/zd* | /dev/zram*) continue ;; esac
        # Empty or unreadable disks have no table; the rest still matter.
        sfdisk -d "$disk" > "partitions-''${disk##*/}.sfdisk" 2> /dev/null || rm -f "partitions-''${disk##*/}.sfdisk"
      done

      zpool status -P > zpool-status.txt
      zpool get -H all > zpool-get.txt
      zfs list -t filesystem,volume -o name,used,volsize,encryptionroot,mountpoint > datasets.txt
      # @blank must exist again before first boot; the root is rolled back to it.
      zfs list -H -t snapshot -d 1 -o name,creation rpool/local/root > root-snapshots.txt
      # Fixed at creation, so never reported as local.
      zfs get -H -t filesystem,volume -o name,property,value encryption,keyformat,volblocksize,normalization,utf8only,casesensitivity > creation-properties.txt
      # Explicitly set or received properties, i.e. what a restore must set again.
      zfs get -H -s local,received -t filesystem,volume -o name,property,value,source all > properties.txt

      # Only replace the previous notes once the new ones are complete.
      rm -rf "$out.old"
      if [ -e "$out" ]; then mv "$out" "$out.old"; fi
      mv "$tmp" "$out"
      rm -rf "$out.old"
    '';
  };
}
