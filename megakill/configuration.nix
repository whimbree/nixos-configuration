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
  sound.enable = lib.mkForce false;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  # Low-latency-sound
  environment.etc."pipewire/pipewire.conf.d/92-low-latency.conf".text = ''
    context.properties = {
      default.clock.rate = 48000
      default.clock.quantum = 32
      default.clock.min-quantum = 32
      default.clock.max-quantum = 384
    }
  '';
  # Low-latency-sound for applications using pulse backend
  environment.etc."pipewire/pipewire-pulse.d/92-low-latency.conf" =
    let json = pkgs.formats.json { };
    in {
      source = json.generate "92-low-latency.conf" {
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
    };
  # Bluetooth codec configuration
  environment.etc."wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
    bluez_monitor.properties = {
      ["bluez5.enable-sbc-xq"] = true,
      ["bluez5.enable-msbc"] = true,
      ["bluez5.enable-hw-volume"] = true,
      ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
    }
  '';

  # Setup users
  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "audio" ];
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
    # stable
    latte-dock
    sierra-breeze-enhanced
    (pkgs.callPackage ./modules/sierrabreeze.nix { })
    # unstable
    unstable.libsForQt5.qtstyleplugin-kvantum
    unstable.libsForQt5.kimageformats
    unstable.libsForQt5.qt5.qtimageformats
    unstable.qt6.qtimageformats
    unstable.libsForQt5.konqueror
    unstable.gnumake
    unstable.gcc
    unstable.gccgo13
    unstable.go
    unstable.gdb
    unstable.lldb
    unstable.clang
    unstable.rustup
    unstable.cmake
    unstable.extra-cmake-modules
    unstable.vim
    unstable.neovim
    unstable.wget
    unstable.git
    unstable.git-repo
    unstable.distrobox
    unstable.curl
    unstable.firefox
    unstable.librewolf
    unstable.chromium
    unstable.killall
    unstable.tree
    unstable.vscode
    unstable.bitwarden
    unstable.spotify
    unstable.discord
    unstable.signal-desktop
    unstable.telegram-desktop
    unstable.element-desktop
    unstable.tailscale
    unstable.clementine
    unstable.yakuake
    unstable.pciutils
    unstable.looking-glass-client
    unstable.lsof
    unstable.neofetch
    unstable.lolcat
    unstable.kde-rounded-corners
    unstable.librewolf
    unstable.tor-browser-bundle-bin
    unstable.sshfs
    unstable.webcamoid
    unstable.zoom-us
    unstable.appimage-run
    unstable.nixpkgs-fmt
    unstable.rnix-lsp
    unstable.mpv
    unstable.vlc
    unstable.monero-gui
    unstable.usbutils
    unstable.nextcloud-client
    unstable.audacity
    unstable.alsa-utils
    unstable.pulseaudio
    unstable.pavucontrol
    unstable.prismlauncher
    unstable.zenmonitor
    unstable.zim
    unstable.qownnotes
    unstable.kfind
    unstable.virtiofsd
    unstable.slack
    unstable.capitaine-cursors
    unstable.lsd
    unstable.tigervnc
    unstable.inetutils
    unstable.blender
    unstable.steam
    unstable.falkon
    unstable.ghc
    unstable.haskell-language-server
    (pkgs.unstable.callPackage ./modules/gpgfrontend.nix { })
    (pkgs.unstable.callPackage ./modules/ksysguard.nix { })
    # nur
    config.nur.repos.dukzcry.gtk3-nocsd
  ];

  boot.extraModulePackages = with config.boot.kernelPackages;
    [ (pkgs.callPackage ./modules/zenpower.nix { inherit kernel; }) ];
  boot.kernelModules = [ "zenpower" ];

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

  systemd.extraConfig = ''
    DefaultTimeoutStopSec=30s
  '';

  # Automatically garbage collect unused packages
  nix.gc = {
    automatic = true;
    randomizedDelaySec = "14m";
    options = "--delete-older-than 28d";
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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}

