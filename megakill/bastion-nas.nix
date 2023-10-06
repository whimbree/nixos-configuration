{ config, pkgs, lib, ... }:

{
  # NFS
  fileSystems."/mnt/backup" = {
    device = "bastion:/export/backup/megakill";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=1800"
    ];
  };

  fileSystems."/home/bree/nas" = {
    device = "bastion:/export/nas/bree";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=1800"
    ];
  };

  fileSystems."/mnt/images" = {
    device = "bastion:/export/images";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=1800"
    ];
  };

  # Samba
  environment.systemPackages = [ pkgs.cifs-utils ];
  fileSystems."/mnt/media" = {
    device = "//bastion/media";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
    in [ "${automount_opts},credentials=/home/bree/.smbcredentials" ];
  };

  fileSystems."/mnt/downloads" = {
    device = "//bastion/downloads";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
    in [ "${automount_opts},credentials=/home/bree/.smbcredentials" ];
  };

  fileSystems."/mnt/public" = {
    device = "//bastion/public";
    fsType = "cifs";
    options = let
      # this line prevents hanging on network split
      automount_opts =
        "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
    in [ "${automount_opts},credentials=/home/bree/.smbcredentials" ];
  };
}
