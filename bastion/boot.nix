{ config, pkgs, lib, ... }: {
  boot.loader.systemd-boot.enable = true;

  # NixOS unstable enabled systemd stage 1 initrd by default. Bastion's scripted
  # initrd hooks below (preLVMCommands, postMountCommands, etc.) are incompatible
  # with systemd stage 1. Explicitly opt out until they are migrated.
  boot.initrd.systemd.enable = false;

  # Kernel modules needed for mounting LUKS devices in initrd stage (igb needed for ethernet) (mlx4_en mlx4_core needed for 10Gbit ethernet)
  boot.initrd.availableKernelModules = [
    "ahci"
    "nvme"
    "usbhid"
    "sd_mod"
    "sr_mod"
    "aesni_intel"
    "cryptd"
    "igb"
    "mlx4_en"
    "mlx4_core"
    # needed for USB SATA JBOD
    "xhci_hcd"
    "uas"
  ];

  # Hardware-level kernel command line. ZFS ARC tuning lives in zfs.nix.
  boot.kernelParams = [
    "nvme_core.default_ps_max_latency_us=0" # Disable NVMe APST to prevent Samsung 990 PRO firmware bug causing drive disconnects
    "pcie_aspm=off" # Disable PCIe Active State Power Management as additional safeguard against NVMe drops
    "pcie_port_pm=off" # Disable PCIe port runtime power management as additional safeguard against NVMe drops
  ];

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
  boot.initrd.postMountCommands = ''
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+baB6WxRgTBFQLoNNcw706A5Egd3gS5hCWl0nMDE+q bree@megakill"
    ];
    hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
  };
}
