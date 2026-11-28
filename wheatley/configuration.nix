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
    ./deploy.nix
    ./host-watch.nix
    ../modules/failure-notify.nix
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
    node = {
      port = 9100;
      scrapeInterval = "60s";
    };
    zfs = {
      port = 9134;
      scrapeInterval = "120s";
    };
    smartctl = {
      port = 9633;
      scrapeInterval = "5m";
    };
  };

  systemd.enableEmergencyMode = false;

  # Lets admins push systems built on another machine (nixos-rebuild
  # --target-host). Grants nothing beyond what sudo already does.
  nix.settings.trusted-users = [ "@wheel" ];  # root is added by default

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

  # No auto-upgrade: with one CPU, wheatley chokes compiling packages that
  # aren't in cache.nixos.org (otelcol-contrib etc.) while serving traffic.
  # Build it on megakill and push it instead:
  #   nixos-rebuild switch --flake 'git+file:///etc/nixos?ref=main#wheatley' \
  #     --target-host bree@wheatley --sudo --ask-sudo-password

  system.stateVersion = "23.05";
}
