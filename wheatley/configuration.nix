{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./persist.nix
    ./sops.nix
    ./virtualization.nix
    ./tailscale.nix
    ./services.nix
    ./backup.nix
  ];

  networking.hostName = "wheatley";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = true;
  networking.enableIPv6 = false;

  systemd.enableEmergencyMode = false;

  time.timeZone = "America/New_York";

  users.users.bree = {
    description = "bree";
    extraGroups = [ "networkmanager" "wheel" ];
    # bree@bastion key is wheatley-specific (not on other hosts)
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
    ];
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    nano
    curl
    inetutils
    killall
    glances
    sysstat
    htop
  ];

  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#wheatley";
    flags = [ "--update-input" "nixpkgs" ];
    operation = "switch";
    dates = "02:00";
  };

  system.stateVersion = "23.05";
}
