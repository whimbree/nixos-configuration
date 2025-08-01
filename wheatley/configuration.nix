# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./persist.nix
    ./virtualization.nix
    ./tailscale.nix
    ./services.nix
    ./backup.nix
  ];

  networking.hostName = "wheatley";
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

  services.openssh = {
    enable = true;
    ports = [ 22 ];
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

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    description = "bree";
    extraGroups = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [

      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMvP4mNeLdbwwnm/3aJoTQ4IJkyS7giH/rpwn//Whqjo bree@pixel6-pro"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
    ];
    hashedPassword =
      "$6$h.WDvL50hbbLP1l0$gs5M9h0kuBW3ZldHMKPlkUFtMJoip5pLZ4RB26z/my1OqbM3DPNe89Cm4EaxQQbvaoSGgNwBZElDcGPD8O.Ii.";
  };
  users.users.root.hashedPassword =
    "$6$y.qkBBBe.ooNUpvc$ehcF2MjH0K72dz2yXQ7ThAlE8fTkmDfhpOIcdEO3M3fL5C9UfUAS6iui6AvrYL.4pZGlWoeGV9tU2Ox8i4eB81";

  environment.systemPackages = with pkgs; [
    git
    vim
    nano
    curl
    inetutils
    killall
    glances
  ];

  # Automatically garbage collect unused packages
  nix.gc = {
    automatic = true;
    randomizedDelaySec = "15m";
    options = "--delete-older-than 30d";
  };

  # Use flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#wheatley";
    flags = [ "--update-input" "nixpkgs" ];
    operation = "switch";
    dates = "02:00";
  };
  nixpkgs.config.allowUnfree = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?
}
