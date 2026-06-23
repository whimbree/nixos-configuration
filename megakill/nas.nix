{ config, pkgs, ... }:

let
  # CIFS mounts read credentials from a sops-rendered file (username=, password=).
  # noperm: don't enforce Unix permissions from the server — let the kernel
  # map everything to the mounting user, avoiding permission mismatches.
  # device-timeout / mount-timeout: fail fast if bastion is unreachable
  # rather than hanging the automount indefinitely.
  cifsBase = "x-systemd.automount,noauto,x-systemd.idle-timeout=1800,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s,iocharset=utf8,noperm";
  cifsOpts = [ "${cifsBase},credentials=${config.sops.templates."smbcredentials".path}" ];
in {

  environment.systemPackages = [ pkgs.cifs-utils ];

  # SMB credentials, sourced from secrets/megakill.yaml and rendered at
  # activation into a root-only file on tmpfs (/run). mount.cifs runs as root,
  # so it can read the rendered file via the credentials= option above.
  sops.defaultSopsFile = ../secrets/megakill.yaml;
  # Read the key from /persist directly, NOT /etc/ssh. Root is rolled back to a
  # blank snapshot on every boot, and the persisted /etc/ssh isn't mounted yet
  # when sops' setupSecrets runs in early activation. /persist is mounted back
  # in initrd (neededForBoot), so the key is available there. (megakill happens
  # to get away with /etc/ssh today only because its sole consumer is a lazy
  # CIFS automount, but this is the robust path.)
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.smb_username = { };
  sops.secrets.smb_password = { };
  sops.secrets.smb_domain = { };
  sops.templates."smbcredentials" = {
    content = ''
      username=${config.sops.placeholder.smb_username}
      password=${config.sops.placeholder.smb_password}
      domain=${config.sops.placeholder.smb_domain}
    '';
    mode = "0400";
  };

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
