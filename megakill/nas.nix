{ pkgs, ... }:

let
  # CIFS mounts read credentials from ~/.smbcredentials (username=, password=).
  # noperm: don't enforce Unix permissions from the server — let the kernel
  # map everything to the mounting user, avoiding permission mismatches.
  # device-timeout / mount-timeout: fail fast if bastion is unreachable
  # rather than hanging the automount indefinitely.
  cifsBase = "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
  cifsOpts = [ "${cifsBase},credentials=/home/bree/.smbcredentials" ];
in {

  environment.systemPackages = [ pkgs.cifs-utils ];

  # All mounts use x-systemd.automount + noauto so they only connect when
  # first accessed, not at boot. This prevents boot hangs if bastion is
  # unreachable (e.g. network split, bastion rebooting).
  # x-systemd.idle-timeout=1800 disconnects after 30 min of inactivity.

  fileSystems."/home/bree/nas" = {
    device = "bastion:/export/nas/bree";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=1800"
      "rsize=131072" # read chunk size (128 KiB) — tuned for gigabit LAN
      "wsize=131072" # write chunk size
      "sync"
    ];
  };

  fileSystems."/mnt/images" = {
    device = "bastion:/export/images";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=1800"
      "rsize=131072"
      "wsize=131072"
      "sync"
    ];
  };

  fileSystems."/mnt/media" = {
    device = "//bastion/media";
    fsType = "cifs";
    options = cifsOpts;
  };

  fileSystems."/mnt/downloads" = {
    device = "//bastion/downloads";
    fsType = "cifs";
    options = cifsOpts;
  };

  fileSystems."/mnt/public" = {
    device = "//bastion/public";
    fsType = "cifs";
    options = cifsOpts;
  };
}
