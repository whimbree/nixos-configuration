{ lib, pkgs, ... }:
let
  # VM configuration - change these per VM
  vmTier = 0;
  vmIndex = 0;
  vmIP = "10.0.${toString vmTier}.${toString vmIndex}"; # sni-proxy

  # Simple MAC generation: 02:00:00:TIER:00:INDEX
  vmMAC = "02:00:00:${lib.fixedWidthString 2 "0" (lib.toHexString vmTier)}:00:${
      lib.fixedWidthString 2 "0" (lib.toHexString vmIndex)
    }";

  vmHostname = "sni-proxy";
in {
  microvm = {
    hypervisor = "cloud-hypervisor";
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;
    # Better compression for store disk
    storeDiskErofsFlags = [ "-zlz4hc,level=5" ];
  };

  boot = {
    # Don't need GRUB in VMs
    loader.grub.enable = false;

    # Required kernel modules for networking
    initrd.kernelModules = [
      "nf_conntrack" # For connection tracking
    ];

    # Optimize for low memory VMs
    kernel.sysctl = lib.optionalAttrs (1024 <= 2 * 1024) {
      # Prevent table overflow in nginx -> service connections
      "net.netfilter.nf_conntrack_max" = lib.mkDefault "65536";
    };

    # Performance optimizations - disable expensive mitigations
    kernelParams = [
      "retbleed=off"
      "gather_data_sampling=off" # Downfall mitigation
    ];
  };

  # Root filesystem is tmpfs - everything ephemeral
  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=1G" "mode=755" ];
  };

  # It is highly recommended to share the host's nix-store
  # with the VMs to prevent building huge images.
  microvm.shares = [{
    source = "/nix/store";
    mountPoint = "/nix/.ro-store";
    tag = "ro-store";
    proto = "virtiofs";
  }];

  # Disable IPv6 globally
  networking.enableIPv6 = false;

  # MicroVM interface configuration  
  microvm.interfaces = [{
    id = "vm${toString (vmTier * 100 + vmIndex)}";
    type = "tap";
    mac = vmMAC;
  }];

  # Static IP configuration with routed networking
  networking = {
    useNetworkd = true;
    hostName = vmHostname;

    # Disable DHCP - we use static IPs
    useDHCP = false;
    dhcpcd.enable = false;
  };

  systemd.network.networks."10-eth" = {
    matchConfig.MACAddress = vmMAC;

    # Static IP based on tier and index
    address = [ "${vmIP}32" ];

    # Routes for internet access through host
    routes = [
      {
        # Route to host (gateway)
        routeConfig = {
          Destination = "10.0.0.0/32";
          GatewayOnLink = true;
        };
      }
      {
        # Default route for internet
        routeConfig = {
          Destination = "0.0.0.0/0";
          Gateway = "10.0.0.0";
          GatewayOnLink = true;
        };
      }
    ];

    networkConfig = {
      # DNS servers (Quad9)
      DNS = [ "9.9.9.9" "149.112.112.112" ];
    };
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      # Only listen on VM's IP
      ListenAddress = vmIP;
    };
  };

  # User configuration - optimized for tmpfs
  users = {
    mutableUsers = false; # Don't allow user changes at runtime

    users = {
      admin = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
        ];
      };

      # Make root home persistent (for bash history, etc.)
      root = {
        createHome = true;
        home = lib.mkForce "/home/root";
      };
    };
  };

  # Create persistent root home directory
  systemd.tmpfiles.rules = [ "d /home/root 0700 root root -" ];

  # Sudo without password for admin user
  security.sudo.wheelNeedsPassword = false;

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # SSH only by default
  };

  # Basic system configuration
  time.timeZone = "UTC";

  # Minimal package set
  environment.systemPackages = with pkgs; [ htop curl wget git nano ];

  # Nix configuration for read-only store
  nix = {
    enable = lib.mkDefault false; # Don't need nix daemon in VMs
    gc.automatic = false; # Can't garbage collect read-only store
    optimise.automatic = false; # Can't optimize read-only store
  };

  # Disable services that don't make sense in VMs
  services.fstrim.enable = false; # No point with tmpfs
  hardware.enableRedistributableFirmware = false; # Not needed in VMs

  # Dummy bootloader install (VMs don't need real bootloader)
  system.build.installBootLoader = lib.getExe' pkgs.coreutils "true";

  # Logging
  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=1month
  '';

  system.stateVersion = "25.05";
}
