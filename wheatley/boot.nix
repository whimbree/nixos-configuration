{ config, pkgs, lib, ... }:

{
  boot.loader.grub = {
    enable = true;
    copyKernels = true;
    zfsSupport = true;
    device = "/dev/vda";
  };

  # Kernel modules needed for mounting LUKS devices in initrd stage.
  # virtio_net is required so the NIC is up for remote LUKS unlock over SSH
  # under systemd stage 1 initrd.
  boot.initrd.availableKernelModules = [ "aesni_intel" "cryptd" "virtio_net" ];

  boot.initrd.luks.devices = {
    cryptkey = {
      device = "/dev/disk/by-uuid/8cac0f80-8059-47db-b131-f79622453527";
    };

    cryptswap = {
      device = "/dev/disk/by-uuid/ab7ea64b-ee73-4f72-a103-ffd33521a5c2";
      keyFile = "/dev/mapper/cryptkey";
      keyFileSize = 64;
    };
  };

  # ensure that rpool is imported at boot
  boot.zfs.devNodes =
    "/dev/disk/by-partuuid/98ec7600-341b-4578-b97c-f4e07b6fae95";
  boot.zfs.forceImportAll = true;

  # cryptsetup must be explicitly bundled into the systemd initrd.
  boot.initrd.systemd.storePaths = [ pkgs.cryptsetup ];

  # rpool's ZFS key is read from /dev/mapper/cryptkey, but NixOS doesn't
  # generate that dependency automatically. Without this, import races against
  # cryptkey opening and fails on first attempt.
  boot.initrd.systemd.services.zfs-import-rpool = {
    after = [ "systemd-cryptsetup@cryptkey.service" ];
    requires = [ "systemd-cryptsetup@cryptkey.service" ];
  };

  # Close cryptkey only after all consumers have finished reading it:
  # cryptswap (LUKS keyfile) and rpool (ZFS key). The "-" prefix tolerates a
  # missing/already-closed device so the service can't fail the boot.
  boot.initrd.systemd.services.close-cryptkey = {
    description = "Close cryptkey LUKS device";
    wantedBy = [ "cryptsetup.target" ];
    after = [
      "systemd-cryptsetup@cryptswap.service"
      "zfs-import-rpool.service"
    ];
    requires = [
      "systemd-cryptsetup@cryptswap.service"
      "zfs-import-rpool.service"
    ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${pkgs.cryptsetup}/bin/cryptsetup close /dev/mapper/cryptkey";
    };
  };

  # Roll back the ephemeral root to the blank snapshot on every boot.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback ZFS root to blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "zfs-import-rpool.service" ];
    before = [ "sysroot.mount" ];
    path = [ pkgs.zfs ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r rpool/local/root@blank
    '';
  };

  # ZFS configuration
  networking.hostId = "52d2d80c";
  boot.supportedFilesystems = [ "zfs" ];

  boot.kernelParams = [
    "zfs.zfs_arc_min=268435456" # ZFS Min ARC Size 256MB
    "zfs.zfs_arc_max=268435456" # ZFS Max ARC Size 256MB
    "elevator=none" # ZFS has it's own scheduler
    "ip=dhcp"
  ];

  # ZFS already has its own scheduler. Without this computer freezes for a second under heavy load.
  services.udev.extraRules = lib.optionalString (config.boot.zfs.enabled) ''
    ACTION=="add|change", KERNEL=="sd[a-z]*[0-9]*|mmcblk[0-9]*p[0-9]*|nvme[0-9]*n[0-9]*p[0-9]*", ENV{ID_FS_TYPE}=="zfs_member", ATTR{../queue/scheduler}="none"
  '';

  # enable LUKS unlock over SSH
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+baB6WxRgTBFQLoNNcw706A5Egd3gS5hCWl0nMDE+q bree@megakill"
      ];
      hostKeys =
        [ "/etc/ssh/ssh_host_ed25519_key" "/etc/ssh/ssh_host_rsa_key" ];
    };
  };
  # copy SSH keys into initrd
  boot.initrd.secrets = {
    "/etc/ssh/ssh_host_ed25519_key" = lib.mkForce "/etc/ssh/ssh_host_ed25519_key";
    "/etc/ssh/ssh_host_rsa_key" = lib.mkForce "/etc/ssh/ssh_host_rsa_key";
  };

}
