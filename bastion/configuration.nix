{ config, lib, pkgs, modulesPath, self, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./filesystem.nix
    ./memory.nix
    ./persist.nix
    ./luks.nix
    ./nas.nix
    ./tailscale.nix
    # ./cockpit.nix
    # ./virtualisation.nix
    ./services.nix
    ./clamav.nix
    ./networking.nix
    ./microvm.nix
    ./microvm-weekly-update.nix
    ./hardware-monitoring.nix
    ./hdd-fan-control.nix
  ];

  # NixOS unstable enabled systemd stage 1 initrd by default. Bastion's
  # luks.nix and filesystem.nix use scripted initrd hooks (preLVMCommands,
  # postMountCommands, etc.) which are incompatible with systemd stage 1.
  # Explicitly opt out until those files are migrated.
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

  networking.hostName = "bastion";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = true;
  networking.enableIPv6 = false;
  # avahi owns mDNS exclusively on bastion; prevent resolved from also claiming it.
  services.resolved.settings.Resolve.MulticastDNS = false;

  systemd.enableEmergencyMode = false;

  time.timeZone = "America/New_York";

  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.rsyslogd.enable = true;
  services.rsyslogd.extraConfig = "auth,authpriv.* -/var/log/auth.log";

  specialisation."X11-KDE".configuration = {
    system.nixos.tags = [ "with-x11-kde" ];
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
  };

  users.users.bree = {
    extraGroups = [ "wheel" ];
    # bastion-only keys: znapzend agents and the Windows workstation
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDoNORnRA7Nr/biUK4ZBQxhHJMgEa0mzcpC/2Gugaxdt root@megakill" # used by znapzend
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYEjogdrnMzIe9njrAwIxubRLosDpRR2UclUmVXQpuY root@wheatley" # used by znapzend
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNtzhIYzBkv5cdYO262Xhtfmp2y5/Es2X1rK1lV+CgY overkill-win"
    ];
  };

  environment.systemPackages = with pkgs; [
    firefox
    killall
    git
    vim
    nano
    curl
    inetutils
    htop
    smartmontools
    glances
    busybox
    fio
    screen
    jq
    iperf3
    sysstat
    gptfdisk
    ddrescue
    tmux
  ];

  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#bastion";
    flags = [ "--update-input" "nixpkgs" ];
    operation = "switch";
    dates = "04:00";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11";
}
