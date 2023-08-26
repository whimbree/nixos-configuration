# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./boot.nix
    ./persist.nix
    ./virtualisation.nix
    ./gpu.nix
    ./tailscale.nix
    ./bastion-nas.nix
  ];

  networking.hostName = "megakill";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  systemd.network.enable = true;

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the Plasma 5 Desktop Environment.
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;

  # Use zsh
  programs.zsh.enable = true;
  environment.shells = with pkgs; [ zsh ];

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = false;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Setup users
  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" ]; # Enable ‘sudo’ for the user.
    hashedPassword =
      "$6$juxnzab1rsHBPVSz$HmoxRiTcbUnUnQ.HbksYniCn5Gdh2fXFFF58J.YCyZhxeIwSzV0aStTgxLC.YOifnxOcyYCsrzvanOq9d7Pl/.";
  };
  users.users.root.initialHashedPassword =
    "$6$BiKGTrkmOT9ib.nm$iuQaQgHUKyLaxScutqafgQydtGXTAosO0Sm/Q9r85nWktggcwRnvDzti8nyGliyAjQrqORLN4swBNsYGvAHM20";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    neovim
    wget
    git
    firefox
    killall
    tree
    vscode
    bitwarden
    chromium
    spotify
    discord
    signal-desktop
    telegram-desktop
    tailscale
    obsidian
    clementine
    yakuake
    pciutils
    looking-glass-client
    latte-dock
    cmake
    extra-cmake-modules
    sierra-breeze-enhanced
    libsForQt5.qtstyleplugin-kvantum
    libsForQt5.kimageformats
    libsForQt5.qt5.qtimageformats
    qt6.qtimageformats
    lsof
    neofetch
    lolcat
    kde-rounded-corners
    nur.repos.dukzcry.gtk3-nocsd
  ];

  # gtk3-nocsd
  environment.variables = {
    GTK_CSD = "0";
    LD_PRELOAD = "/run/current-system/sw/lib/libgtk3-nocsd.so.0";
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball
      "https://github.com/nix-community/NUR/archive/master.tar.gz") {
        inherit pkgs;
      };
  };

  fonts = {
    packages = with pkgs; [
      (pkgs.callPackage ./modules/apple_fonts.nix { })
      fira-code
      source-code-pro
      source-sans-pro
      source-serif-pro
    ];
    fontconfig = {
      defaultFonts = {
        monospace = [ "SF Mono" ];
        sansSerif = [ "SF Pro Display" ];
        serif = [ "SF Pro Display" ];
      };
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
  system.autoUpgrade = {
    enable = true;
    channel = "https://nixos.org/channels/nixos-unstable";
    dates = "daily";
    operation = "boot";
  };

  nix.gc = {
    automatic = true;
    randomizedDelaySec = "14m";
    options = "--delete-older-than 10d";
  };

}

