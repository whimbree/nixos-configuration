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
    # re-enable once Tailscale is connected and bastion is reachable by hostname
    # ./nas.nix
    # ./backup.nix
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

  # SSH: key-only authentication, no root login, verbose logging for audit trail.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      LogLevel = "VERBOSE";
    };
  };

  # pcscd: smartcard daemon required for the Yubikey to work in CCID/smartcard
  # mode (e.g. GPG smartcard, PIV). Without it, only FIDO2/OTP modes work.
  services.pcscd.enable = true;

  services.sysstat.enable = true;

  # Reduce the default stop timeout from 90s. Services that hang on shutdown
  # will be killed after 30s instead of making the shutdown take forever.
  systemd.settings.Manager.DefaultTimeoutStopSec = "30s";

  systemd.enableEmergencyMode = true;

  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "audio" "adbusers" "kvm" "dialout" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvP4mNeLdbwwnm/3aJoTQ4IJkyS7giH/rpwn//Whqjo bree@pixel6-pro"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH+baB6WxRgTBFQLoNNcw706A5Egd3gS5hCWl0nMDE+q bree@megakill"
    ];
    hashedPassword =
      "$6$MZan.byHfwfSq7qI$F9e9vqNgWyN8dalDpHBHt2DC6FSRqbJ5l1m5grvh/kZno55uH697FykRWiQzP6b0U58Ol2n3k2EHAjY.9Ligg1";
  };
  users.users.root.hashedPassword =
    "$6$92pB6eAOE8ZHfqih$aMjx7DKyP2YdLokS0E3VN2ZfnQYWO1I46VwdoLfGB2Xy3m8DgJTF8/8vT6b6zRPfhG/Xs.5YSQcQmTHUyDiat1";

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

  # Prevent git "dubious ownership" errors when nixos-rebuild runs git as root
  # against /etc/nixos, which is owned by bree (via the /persist bind mount).
  environment.etc."gitconfig".text = ''
    [safe]
      directory = /etc/nixos
  '';

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
    extra-cmake-modules
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

  nix.gc = {
    automatic = true;
    randomizedDelaySec = "15m";
    options = "--delete-older-than 60d";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.sandbox = true;

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

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  system.stateVersion = "25.11";
}
