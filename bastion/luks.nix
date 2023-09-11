{ config, pkgs, lib, ... }: {
  boot.initrd.preLVMCommands = lib.mkOrder 400 "sleep 1";

  boot.initrd.network.postCommands = ''
    until ip link set enp1s0 up; do sleep .1; done
    ip addr add 192.168.69.59/24 dev enp1s0
    ip route add default via 192.168.69.1 dev enp1s0
  '';

  # open cryptkey and cryptswap in initrd boot stage
  boot.initrd.luks.devices = {
    cryptkey = {
      device = "/dev/disk/by-uuid/5716e9ea-295b-4ee1-9f33-9c403a853ca1";
    };

    cryptswap = {
      device = "/dev/disk/by-uuid/c71ba86c-74e1-4b56-8b2c-d6669a8d9dc5";
      keyFile = "/dev/mapper/cryptkey";
      keyFileSize = 64;
    };
  };

  # close cryptkey at end of initrd boot stage
  boot.initrd.postMountCommands = "cryptsetup close /dev/mapper/cryptkey";

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
