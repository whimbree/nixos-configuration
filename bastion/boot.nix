{ config, pkgs, lib, ... }: {
  boot.loader.systemd-boot.enable = true;

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

  # cryptkey is a small LUKS device unlocked by passphrase; its decrypted
  # payload is consumed as a raw key (keyFile) by cryptswap and the ZFS pools.
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

  # TEMPORARY: passwordless root shell on the console/BMC if the initrd fails.
  # Remove once the systemd-initrd migration has booted cleanly.
  boot.initrd.systemd.emergencyAccess = true;

  # cryptsetup must be explicitly bundled into the systemd initrd.
  boot.initrd.systemd.storePaths = [ pkgs.cryptsetup ];

  # Close cryptkey only after all consumers have finished reading it:
  # - cryptswap reads 64 bytes as its LUKS keyfile
  # - rpool loads its ZFS native encryption key from it (hard dependency)
  # - ocean and neptune also read their keys from it, but their mounts are
  #   nofail: wants= so a slow/absent JBOD doesn't fail sysroot.mount
  # The zfs-import-* ordering deps reference units defined in zfs.nix. The "-"
  # prefix tolerates a missing/already-closed device so the service can't fail
  # the boot.
  boot.initrd.systemd.services.close-cryptkey = {
    description = "Close cryptkey LUKS device";
    wantedBy = [ "cryptsetup.target" ];
    after = [
      "systemd-cryptsetup@cryptswap.service"
      "zfs-import-rpool.service"
      "zfs-import-ocean.service"
      "zfs-import-neptune.service"
    ];
    requires = [
      "systemd-cryptsetup@cryptswap.service"
      "zfs-import-rpool.service"
    ];
    wants = [
      "zfs-import-ocean.service"
      "zfs-import-neptune.service"
    ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${pkgs.cryptsetup}/bin/cryptsetup close /dev/mapper/cryptkey";
    };
  };

  # enable LUKS unlock over SSH
  boot.initrd.network = {
    enable = true;
    # Hand enp1s0 to stage 2's networkd (DHCP) without the initrd's static
    # address lingering.
    flushBeforeStage2 = true;
    ssh = {
      enable = true;
      port = 22;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+baB6WxRgTBFQLoNNcw706A5Egd3gS5hCWl0nMDE+q bree@megakill"
      ];
      # Copied into the initrd via boot.initrd.secrets by the ssh module.
      hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  # Static address on the 10G NIC for remote unlock.
  boot.initrd.systemd.network.networks."10-enp1s0" = {
    matchConfig.Name = "enp1s0";
    address = [ "192.168.69.59/24" ];
    gateway = [ "192.168.69.1" ];
    linkConfig.RequiredForOnline = "routable";
  };
}
