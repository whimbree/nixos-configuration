# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, lib, btc-clients-pkgs, ... }:

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
    ./backup.nix
    ./services.nix
  ];

  networking.hostName = "megakill";
  networking.networkmanager.enable = true;
  networking.useDHCP = lib.mkDefault true;
  networking.useNetworkd = true;
  networking.firewall.enable = true;
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
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.desktopManager.plasma6.enableQt5Integration = true;
  # Start Plasma Sessions in Wayland
  # services.xserver.displayManager.defaultSession = "plasmawayland";

  programs.kdeconnect.enable = true;

  # Use zsh
  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };

  # Enable bluetooth
  hardware.bluetooth = {
    enable = true;
    settings = { General = { Enable = "Source,Sink,Media,Socket"; }; };
  };

  # Enable sound via pipewire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  # Low-latency-sound
  services.pipewire.extraConfig.pipewire."92-low-latency" = {
    context.properties = {
      default.clock.rate = 48000;
      default.clock.quantum = 32;
      default.clock.min-quantum = 32;
      default.clock.max-quantum = 384;
    };
  };
  # Low-latency-sound for applications using pulse backend
  services.pipewire.extraConfig.pipewire-pulse."92-low-latency" = {
    context.modules = [{
      name = "libpipewire-module-protocol-pulse";
      args = {
        pulse.min.req = "32/48000";
        pulse.default.req = "32/48000";
        pulse.max.req = "384/48000";
        pulse.min.quantum = "32/48000";
        pulse.max.quantum = "384/48000";
      };
    }];
    stream.properties = {
      node.latency = "32/48000";
      resample.quality = 1;
    };
  };
  # Bluetooth codec configuration
  services.pipewire.wireplumber.configPackages = [
    (pkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/51-bluez-config.lua" ''
      bluez_monitor.properties = {
        ["bluez5.enable-sbc-xq"] = true,
        ["bluez5.enable-msbc"] = true,
        ["bluez5.enable-hw-volume"] = true,
        ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
      }
    '')
  ];

  # Setup users
  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "audio" "adbusers" "kvm" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvP4mNeLdbwwnm/3aJoTQ4IJkyS7giH/rpwn//Whqjo bree@pixel6-pro"
    ];
    hashedPassword =
      "$6$MZan.byHfwfSq7qI$F9e9vqNgWyN8dalDpHBHt2DC6FSRqbJ5l1m5grvh/kZno55uH697FykRWiQzP6b0U58Ol2n3k2EHAjY.9Ligg1";
  };
  users.users.root.hashedPassword =
    "$6$L3Due0wwEsZQASqy$uLFJWS4YsOisalzT2JOEWjAhQiT8XDzQ4Hg/QkpOQDMax9pzOdtieQsjQL..JyBbAQA9Y/sDoVKMHQb8wdVId1";

  environment.systemPackages = with pkgs; [
    libsForQt5.qtstyleplugin-kvantum
    # libsForQt5.kimageformats
    kdePackages.kimageformats
    libsForQt5.qt5.qtimageformats
    qt6Packages.qtstyleplugin-kvantum
    qt6.qtimageformats
    # libsForQt5.konqueror
    kdePackages.konqueror
    sysstat
    gnumake
    zip
    unzip
    # vcpkg
    gcc
    gccgo13
    go
    gdb
    lldb
    clang
    clang-tools
    rustup
    nixd
    cmake
    extra-cmake-modules
    vim
    neovim
    wget
    git
    git-repo
    distrobox
    curl
    firefox
    librewolf
    chromium
    killall
    tree
    vscode
    code-cursor
    zed-editor
    bitwarden-desktop
    spotify
    discord
    signal-desktop
    telegram-desktop
    element-desktop
    tailscale
    strawberry
    pciutils
    looking-glass-client
    lsof
    neofetch
    lolcat
    kde-rounded-corners
    librewolf
    tor-browser
    sshfs
    webcamoid
    appimage-run
    nixpkgs-fmt
    mpv
    vlc
    monero-gui
    usbutils
    nextcloud-client
    audacity
    alsa-utils
    pulseaudio
    pavucontrol
    prismlauncher
    # zenmonitor
    zim
    qownnotes
    kdePackages.kfind
    virtiofsd
    slack
    capitaine-cursors
    lsd
    tigervnc
    inetutils
    blender
    steam
    kdePackages.falkon
    ghc
    haskell-language-server
    # latte-dock
    plasma-panel-colorizer
    # sierra-breeze-enhanced
    # kdePackages.sierra-breeze-enhanced
    zoom-us
    bisq2
    wasabiwallet
    temurin-bin-17
    htop
    smartmontools
    wineWowPackages.stable
    texliveFull
    glances
    yubikey-manager
    yubioath-flutter
    yubikey-personalization
    mpich
    llvmPackages.openmp
    libreoffice-qt
    kdePackages.konsole
    kdePackages.yakuake
    android-tools
    bind
    reaper
    calibre
    aseprite
    pdfarranger
    masterpdfeditor
    # (pkgs.callPackage ./modules/sierrabreeze.nix { })
    # (pkgs.callPackage ./modules/gpgfrontend.nix { })
    # (pkgs.callPackage ./modules/ksysguard.nix { })
    bisq
    racket
    # nur
    # nur.repos.dukzcry.gtk3-nocsd

  ];

  programs.direnv.enable = true;

  boot.extraModulePackages = with config.boot.kernelPackages;
    [ (pkgs.callPackage ./modules/zenpower.nix { inherit kernel; }) ];
  boot.kernelModules = [ "zenpower" ];

  # gtk3-nocsd (only works with X11)
  # environment.variables = {
  #   GTK_CSD = "0";
  #   LD_PRELOAD =
  #     "${pkgs.nur.repos.dukzcry.gtk3-nocsd}/lib/libgtk3-nocsd.so.0";
  # };

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
        monospace = [ "Fira Code" ];
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
    pinentryPackage = pkgs.pinentry-qt;
  };

  # Enable the OpenSSH daemon.
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

  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "30s";
  };

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
    flake = "/etc/nixos#megakill";
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
    operation = "switch";
    dates = "04:00";
  };
  nix.settings.sandbox = true;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  services.sysstat.enable = true;

  # Needed to use the smart card mode (CCID) of Yubikey
  services.pcscd.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}

