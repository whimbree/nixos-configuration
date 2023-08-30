# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, lib, ... }:

{
  imports = [
    # Include the results of the hardware scan.
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
  systemd.network.wait-online.enable = false;

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
  # Start Plasma Sessions in Wayland
  # services.xserver.displayManager.defaultSession = "plasmawayland";

  programs.kdeconnect.enable = true;

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

  # Enable bluetooth
  hardware.bluetooth = {
    enable = true;
    settings = { General = { Enable = "Source,Sink,Media,Socket"; }; };
  };

  # Enable sound
  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
    support32Bit = true;
    package = pkgs.pulseaudioFull;
  };
  nixpkgs.config.pulseaudio = true;

  # Setup users
  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "audio" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
    ];
    hashedPassword =
      "$6$MZan.byHfwfSq7qI$F9e9vqNgWyN8dalDpHBHt2DC6FSRqbJ5l1m5grvh/kZno55uH697FykRWiQzP6b0U58Ol2n3k2EHAjY.9Ligg1";
  };
  users.users.root.hashedPassword =
    "$6$L3Due0wwEsZQASqy$uLFJWS4YsOisalzT2JOEWjAhQiT8XDzQ4Hg/QkpOQDMax9pzOdtieQsjQL..JyBbAQA9Y/sDoVKMHQb8wdVId1";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    gnumake
    gcc
    gccgo13
    go
    gdb
    lldb
    clang
    rustup
    cmake
    extra-cmake-modules
    vim
    neovim
    wget
    git
    firefox
    librewolf
    chromium
    killall
    tree
    vscode
    bitwarden
    spotify
    discord
    signal-desktop
    telegram-desktop
    element-desktop
    tailscale
    obsidian
    clementine
    yakuake
    pciutils
    looking-glass-client
    latte-dock
    sierra-breeze-enhanced
    libsForQt5.qtstyleplugin-kvantum
    libsForQt5.kimageformats
    libsForQt5.qt5.qtimageformats
    qt6.qtimageformats
    lsof
    neofetch
    lolcat
    kde-rounded-corners
    config.nur.repos.dukzcry.gtk3-nocsd
    obsidian
    librewolf
    tor-browser-bundle-bin
    mailspring
    sshfs
    webcamoid
    zoom-us
    appimage-run
    nixpkgs-fmt
    rnix-lsp
    mpv
    vlc
    monero-gui
    usbutils
    nextcloud-client
    audacity
    alsa-utils
    pulseaudio
    pavucontrol
    capitaine-cursors
    (pkgs.callPackage ./modules/breeze-enhanced.nix { })
    (pkgs.callPackage ./modules/gpgfrontend.nix { })
    (pkgs.callPackage ./modules/sierrabreeze.nix { })
  ];

  # gtk3-nocsd (only works with X11)
  environment.variables = {
    GTK_CSD = "0";
    LD_PRELOAD =
      "${config.nur.repos.dukzcry.gtk3-nocsd}/lib/libgtk3-nocsd.so.0";
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

  # Automatically garbage collect unused packages
  nix.gc = {
    automatic = true;
    randomizedDelaySec = "14m";
    options = "--delete-older-than 10d";
  };

  # Use flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#megakill";
    flags = [ "--update-input" "nixpkgs" ];
    dates = "daily";
    operation = "boot";
  };
  nixpkgs.config.allowUnfree = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}

