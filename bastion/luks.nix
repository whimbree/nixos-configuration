{ config, pkgs, lib, ... }: {
  boot.initrd.preLVMCommands = lib.mkOrder 400 "sleep 1";

  boot.initrd.network.postCommands = ''
    if ip link show enp1s0 &> /dev/null; then
      until ip link set enp1s0 up; do sleep .1; done
      ip addr add 192.168.69.59/24 dev enp1s0
      ip route add default via 192.168.69.1 dev enp1s0
    fi
  '';

  # open cryptkey and cryptswap in initrd boot stage
  boot.initrd.luks.devices = {
    cryptkey = {
      device = "/dev/disk/by-uuid/37b2608c-e466-4a86-b629-1570e81e3932";
    };

    cryptswap = {
      device = "/dev/disk/by-uuid/e14d38d2-9b46-4f70-a2f1-42d8c292b681";
      keyFile = "/dev/mapper/cryptkey";
      keyFileSize = 64;
    };
  };

  # close cryptkey at end of initrd boot stage
  # ensure our ZFS pools were imported before closing cryptkey
  boot.initrd.postMountCommands = ''
    zfs load-key ocean neptune
    [ -z "$(zpool list -H -o name ocean)" ] && zpool import -f ocean
    [ -z "$(zpool list -H -o name neptune)" ] && zpool import -f neptune
    cryptsetup close /dev/mapper/cryptkey
  '';

  # enable LUKS unlock over SSH
  boot.initrd.network.enable = true;
  # copy SSH key into initrd
  boot.initrd.secrets = { "/persist/etc/secrets/initrd/ssh_host_ed25519_key" = "/persist/etc/secrets/initrd/ssh_host_ed25519_key"; };

  boot.initrd.network.ssh = {
    enable = true;
    port = 22;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
    ];
    hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
  };
}