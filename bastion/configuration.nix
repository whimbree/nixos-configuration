{ config, lib, pkgs, modulesPath, self, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./filesystem.nix
    ./persist.nix
    ./luks.nix
    ./nas.nix
    ./tailscale.nix
    ./cockpit.nix
    ./virtualisation.nix
    ./services.nix
    ./clamav.nix
    ./networking.nix
    ./microvm.nix
  ];

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
  networking.useNetworkd = true;
  networking.firewall.enable = true;
  networking.enableIPv6 = false;
  systemd.network.enable = true;
  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
  networking.nameservers =
    [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    extraConfig = ''
      DNSOverTLS=yes
    '';
  };

  systemd.enableEmergencyMode = false;

  time.timeZone = "America/New_York";

  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      # require public key authentication for better security
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      LogLevel = "VERBOSE";
    };
  };

  systemd.extraConfig = ''
    DefaultTimeoutStopSec=30s
  '';

  services.rsyslogd.enable = true;
  services.rsyslogd.extraConfig = "auth,authpriv.* -/var/log/auth.log";

  specialisation."X11-KDE".configuration = {
    system.nixos.tags = [ "with-x11-kde" ];
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
  };

  users.mutableUsers = false;

  users.users.bree = {
    isNormalUser = true;
    home = "/home/bree";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvP4mNeLdbwwnm/3aJoTQ4IJkyS7giH/rpwn//Whqjo bree@pixel6-pro"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICHM4Amtsji8xhwDBoa0+ksntNKSAnET9VYAq9ihyFrw root@megakill" # used by znapzend
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYEjogdrnMzIe9njrAwIxubRLosDpRR2UclUmVXQpuY root@wheatley" # used by znapzend
    ];
    hashedPassword =
      "$6$qUgza/1z1AzqiXCU$5QvUzVCAGY0FslF.hamAUXyAHDnGd3wZK.qAhMHXNWMJ961BwLNrGHWHBnnNBdtJPewM9KwSO3Xe1zQNgfQWA.";
  };
  users.users.root.hashedPassword =
    "$6$92pB6eAOE8ZHfqih$aMjx7DKyP2YdLokS0E3VN2ZfnQYWO1I46VwdoLfGB2Xy3m8DgJTF8/8vT6b6zRPfhG/Xs.5YSQcQmTHUyDiat1";

  environment.systemPackages = with pkgs; [
    firefox
    killall
    git
    vim
    nano
    curl
    inetutils
    killall
    htop
    smartmontools
    glances
  ];

  # Automatically garbage collect unused packages
  nix.gc = {
    automatic = true;
    randomizedDelaySec = "15m";
    options = "--delete-older-than 60d";
  };

  # Use flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#bastion";
    flags = [ "--update-input" "nixpkgs" ];
    operation = "switch";
    dates = "04:00";
  };
  nixpkgs.config.allowUnfree = true;

  services.sysstat.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11";
}
