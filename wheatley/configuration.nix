{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./boot.nix
    ./zfs.nix
    ./memory.nix
    ./persist.nix
    ./sops.nix
    ./virtualisation.nix
    ./tailscale.nix
    ./services.nix
    ./backup.nix
    ../modules/observability-nginx.nix
  ];

  networking.hostName = "wheatley";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = true;
  networking.enableIPv6 = false;

  # Hardware/ZFS health exporters, localhost-only, scraped by the agent.
  # No IPMI here: this chassis has no BMC.
  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "127.0.0.1";
      enabledCollectors = [ "systemd" ];
    };
    zfs = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
    smartctl = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
  };

  # nginx structured access logging + agent fileLogs come from the shared
  # modules/observability-nginx.nix imported above.
  homelab.observabilityAgent.prometheusScrapes = {
    node = 9100;
    zfs = 9134;
    smartctl = 9633;
  };

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
