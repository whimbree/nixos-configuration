{ config, pkgs, lib, ... }:

{
  # NFS
  fileSystems."/mnt/backup" = {
    device = "192.168.69.59:/backup/megakill";
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

  fileSystems."/home/bree/nas" = {
    device = "192.168.69.59:/nas/bree";
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

  fileSystems."/mnt/images" = {
    device = "192.168.69.59:/images";
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

  # Samba
  environment.systemPackages = [ pkgs.cifs-utils ];
  fileSystems."/mnt/media" = {
    device = "//192.168.69.59/media";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
    in [ "${automount_opts},credentials=/home/bree/.smbcredentials" ];
  };

  fileSystems."/mnt/downloads" = {
    device = "//192.168.69.59/downloads";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
    in [ "${automount_opts},credentials=/home/bree/.smbcredentials" ];
  };

  fileSystems."/mnt/public" = {
    device = "//192.168.69.59/public";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
    in [ "${automount_opts},credentials=/home/bree/.smbcredentials" ];
  };
}
