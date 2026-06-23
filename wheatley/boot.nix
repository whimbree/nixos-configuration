{ config, pkgs, lib, ... }:

{
  boot.loader.grub = {
    enable = true;
    copyKernels = true;
    zfsSupport = true;
    device = "/dev/vda";
  };

  boot.initrd.systemd.enable = true;

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

  # cryptsetup must be explicitly bundled into the systemd initrd.
  boot.initrd.systemd.storePaths = [ pkgs.cryptsetup ];

  # Close cryptkey only after all consumers have finished reading it:
  # cryptswap (LUKS keyfile) and rpool (ZFS key, ordered in zfs.nix). The "-"
  # prefix tolerates a missing/already-closed device so the service can't fail
  # the boot.
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

  # ip=dhcp brings the NIC up in initrd for remote LUKS unlock over SSH.
  boot.kernelParams = [ "ip=dhcp" ];

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
}
