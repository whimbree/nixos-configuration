{ config, lib, pkgs, ... }: {

  imports = [
    ./hardware-configuration.nix
    ./zfs.nix
    ./persist.nix
    ./tailscale.nix
    ./networking.nix
    ./audio.nix
    ./gpu.nix
    ./virtualisation.nix
    ./nas.nix
    ./backup.nix
  ];

  networking.hostName = "megakill";

  time.timeZone = "America/New_York";

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

  services.xserver.enable = true;
  services.xserver.xkb = { layout = "us"; variant = ""; };
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;

  # CUPS printing with HP driver support.
  services.printing = {
    enable = true;
    drivers = [ pkgs.hplip ];
  };

  # pcscd: smartcard daemon required for the Yubikey to work in CCID/smartcard
  # mode (e.g. GPG smartcard, PIV). Without it, only FIDO2/OTP modes work.
  services.pcscd.enable = true;

  systemd.enableEmergencyMode = true;

  users.users.bree = {
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "audio" "adbusers" "kvm" "dialout" ];
  };

  programs.zsh.enable = true;
  environment.shells = [ pkgs.zsh ];

  programs.kdeconnect.enable = true;
  programs.direnv.enable = true;
  programs.mtr.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-qt;
  };

  # zenpower: out-of-tree kernel module that exposes AMD Ryzen CPU power/voltage
  # readings to the hwmon subsystem (visible via `sensors`). The upstream
  # k10temp driver only provides temperature on Zen 2+.
  boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];
  boot.kernelModules = [ "zenpower" ];

  fonts = {
    packages = with pkgs; [
      (pkgs.callPackage ./modules/apple_fonts.nix { })
      fira-code
      source-code-pro
      source-sans-pro
      source-serif-pro
    ];
    fontconfig.defaultFonts = {
      monospace = [ "Fira Code" ];
      sansSerif = [ "SF Pro Display" ];
      serif = [ "SF Pro Display" ];
    };
  };

  environment.systemPackages = with pkgs; [
    # KDE / Qt extras
    kdePackages.kimageformats
    qt6Packages.qtstyleplugin-kvantum
    qt6.qtimageformats

    # Development
    sysstat
    gnumake
    zip
    unzip
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
    kdePackages.extra-cmake-modules
    vim
    neovim
    wget
    git
    git-repo
    curl
    ghc
    haskell-language-server
    racket
    conda
    nixfmt
    nixpkgs-fmt
    mpich
    llvmPackages.openmp
    temurin-bin-17

    # System tools
    killall
    tree
    lsof
    pciutils
    usbutils
    inetutils
    bind
    sshfs
    lsd
    htop
    glances
    fastfetch
    lolcat
    smartmontools
    appimage-run
    android-tools

    # Desktop / productivity
    firefox
    librewolf
    chromium
    tor-browser
    vscode
    code-cursor
    zed-editor
    bitwarden-desktop
    spotify
    discord
    signal-desktop
    telegram-desktop
    element-desktop
    slack
    zoom-us
    libreoffice-qt-fresh
    kdePackages.konsole
    kdePackages.yakuake
    kdePackages.kfind
    kdePackages.falkon
    plasma-panel-colorizer
    capitaine-cursors

    # Media
    mpv
    vlc
    strawberry
    audacity
    reaper
    alsa-utils
    pavucontrol
    pulseaudio   # CLI tools (pactl etc.) alongside pipewire-pulse
    webcamoid
    blender

    # Gaming
    steam
    wineWow64Packages.stable
    prismlauncher
    looking-glass-client
    tigervnc

    # Virtualisation (UI tools; daemon config is in virtualisation.nix)
    virtiofsd
    distrobox

    # Finance / crypto
    bisq2
    wasabiwallet
    monero-gui

    # Productivity / notes
    zim
    qownnotes

    # Yubikey
    yubikey-manager
    yubioath-flutter
    yubikey-personalization

    # Misc
    texliveFull
    pdfarranger
    masterpdfeditor
    aseprite
    nextcloud-client
  ];

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

  nixpkgs.config.allowBroken = true;
  # bitwarden-desktop currently pulls in electron 39.x, flagged EOL/insecure upstream.
  nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

  system.stateVersion = "25.11";
}
