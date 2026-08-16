{ config, lib, pkgs, modulesPath, self, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./boot.nix
    ./filesystem.nix
    ./zfs.nix
    ./memory.nix
    ./persist.nix
    ./nas.nix
    ./tailscale.nix
    # ./cockpit.nix
    # ./virtualisation.nix
    ./services.nix
    ./clamav.nix
    ./networking.nix
    ./observability-host.nix
    ./microvm.nix
    ./modules/sops-vm-keys.nix
    ./microvm-weekly-update.nix
    ./hardware-monitoring.nix
    ./hdd-fan-control.nix
    ./vfio.nix
  ];

  networking.hostName = "bastion";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = true;
  networking.enableIPv6 = false;
  # avahi owns mDNS exclusively on bastion; prevent resolved from also claiming it.
  services.resolved.settings.Resolve.MulticastDNS = false;

  systemd.enableEmergencyMode = false;

  time.timeZone = "America/New_York";

  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.rsyslogd.enable = true;
  services.rsyslogd.extraConfig = ''
    $FileOwner root
    $FileGroup systemd-journal
    $FileCreateMode 0640
    auth,authpriv.* -/var/log/auth.log
  '';
  systemd.tmpfiles.rules = [
    "z /var/log/auth.log 0640 root systemd-journal -"
    # clamonacc runs as root and creates its log with default modes; the
    # observability agent reads these via its clamav supplementary group.
    # `d` (not `z`) so the directory is created if absent.
    "d /var/log/clamav 0750 clamav clamav -"
    "z /var/log/clamav/*.log 0640 - clamav -"
  ];
  services.logrotate.settings.auth-log = {
    files = [ "/var/log/auth.log" ];
    frequency = "daily";
    maxsize = "128M";
    rotate = 14;
    compress = true;
    delaycompress = true;
    create = "0640 root systemd-journal";
    postrotate = "${pkgs.systemd}/bin/systemctl kill -s HUP syslog.service >/dev/null 2>&1 || true";
  };

  # Hardware/ZFS health exporters, localhost-only, scraped by the agent:
  # pool capacity is this host's most operationally proven risk, and SMART/
  # IPMI cover the disks and chassis the pools live on.
  services.prometheus.exporters = {
    node = {
      enable = true;
      listenAddress = "127.0.0.1";
      # Defaults already include zfs (ARC), hwmon, thermal; systemd adds
      # unit-state metrics (failed units) on top.
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
    ipmi = {
      enable = true;
      listenAddress = "127.0.0.1";
    };
  };

  homelab.observabilityAgent = {
    supplementaryGroups = [ "clamav" ];
    prometheusScrapes = {
      node = 9100;
      zfs = 9134;
      smartctl = 9633;
      ipmi = 9290;
    };
    fileLogs = {
      auth = {
        include = [ "/var/log/auth.log" ];
        serviceName = "authentication";
      };
      clamav = {
        include = [ "/var/log/clamav/*.log" ];
        serviceName = "clamav";
      };
    };
  };

  specialisation."X11-KDE".configuration = {
    system.nixos.tags = [ "with-x11-kde" ];
    services.xserver.enable = true;
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
  };

  users.users.bree = {
    extraGroups = [ "wheel" ];
    # bastion-only keys: znapzend agents and the Windows workstation
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDoNORnRA7Nr/biUK4ZBQxhHJMgEa0mzcpC/2Gugaxdt root@megakill" # used by znapzend
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYEjogdrnMzIe9njrAwIxubRLosDpRR2UclUmVXQpuY root@wheatley" # used by znapzend
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNtzhIYzBkv5cdYO262Xhtfmp2y5/Es2X1rK1lV+CgY overkill-win"
    ];
  };

  environment.systemPackages = with pkgs; [
    firefox
    killall
    git
    vim
    nano
    curl
    inetutils
    htop
    smartmontools
    glances
    busybox
    fio
    screen
    jq
    iperf3
    sysstat
    gptfdisk
    ddrescue
    tmux
  ];

  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#bastion";
    flags = [ "--update-input" "nixpkgs" ];
    operation = "switch";
    dates = "04:00";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.11";
}
