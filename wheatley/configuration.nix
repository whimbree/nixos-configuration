# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./persist.nix
    ./virtualization.nix
    ./tailscale.nix
    ./services.nix
  ];

  networking.hostName = "wheatley";
  networking.firewall.enable = true;

  time.timeZone = "America/New_York";

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

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.mutableUsers = false;
  users.users.bree = {
    isNormalUser = true;
    description = "bree";
    extraGroups = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
    ];
    hashedPassword =
      "$6$/h23wDvryt1VGo9g$gCfRQwaCa0NiJKwNW/4sF1xfQluA0Q.IV/BoUXyb8wQoOSred5HzT9FD0d5nsSaofWSpc7o9U7mWaogbEvP8C1";
  };
  users.users.root.hashedPassword =
    "$6$MLr/jIlMdOWnAjaf$ZY/yMIbC87KssW.T.hlWr0nAMtcrto311Jxf2TZv6XtcIxGmLe.xJ1mglv4BwDYTRB5fBjvv1iBO5GuUs9tdg1";

  environment.systemPackages = with pkgs; [ git vim nano curl ];

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
    flake = "/etc/nixos#wheatley";
    flags = [ "--update-input" "nixpkgs" ];
    dates = "weekly";
    operation = "switch";
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
