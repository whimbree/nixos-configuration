# Common configuration for all MicroVMs

{ config, lib, pkgs, ... }:

{
  boot = {
    # Don't need GRUB in VMs
    loader.grub.enable = false;

    # Required kernel modules for networking
    initrd.kernelModules = [
      "nf_conntrack" # For connection tracking
    ];

    # Optimize for low memory VMs - prevent connection table overflow
    kernel.sysctl = lib.optionalAttrs (config.microvm.mem <= 2 * 1024) {
      # Prevents "nf_conntrack: table full, dropping packet" in nginx
      "net.netfilter.nf_conntrack_max" = lib.mkDefault "65536";
    };

    # Performance optimizations - disable expensive mitigations in VMs
    kernelParams = [
      "retbleed=off"
      "gather_data_sampling=off" # Downfall mitigation
    ];
  };

  # Default to tmpfs root for stateless VMs
  fileSystems."/" = lib.mkForce {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "size=1G" "mode=755" ];
  };

  # Share host's nix store for efficiency
  microvm.shares = lib.mkDefault [{
    source = "/nix/store";
    mountPoint = "/nix/.ro-store";
    tag = "ro-store";
    proto = "virtiofs";
  }];

  # MicroVM optimizations
  microvm = {
    # Better compression for store disk
    storeDiskErofsFlags = lib.mkDefault [ "-zlz4hc,level=5" ];

    # Default hypervisor
    hypervisor = lib.mkDefault "cloud-hypervisor";

    # Default resource allocation (can be overridden per VM)
    mem = lib.mkDefault 512;
    hotplugMem = lib.mkDefault 1024;
    vcpu = lib.mkDefault 2;
  };

  # Default networking configuration
  networking = {
    enableIPv6 = false; # Disable IPv6 globally
    useNetworkd = lib.mkDefault true; # VMs use systemd-networkd
  };

  # User management optimized for tmpfs
  users = {
    mutableUsers = false; # Users defined declaratively only
    users = {
      # Default admin user (can be extended per VM)
      admin = lib.mkDefault {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINfnYIsi2Obl8sSRYvyoUHPRanfUqwMhtp9c79tQofkZ whimbree@pm.me"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrGLqe44/P8mmy9AwOSDoYwZ5AfppwGW1WLptSbqO9M bree@bastion"
        ];
      };

      # Make root home persistent for bash history, etc.
      root = {
        createHome = true;
        home = lib.mkForce "/home/root";
      };
    };
  };

  # Create persistent directories
  systemd.tmpfiles.rules = [
    "d /home/root 0700 root root -" # Root home directory
  ];

  # SSH configuration with persistent host keys
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };

    # Use persistent host keys
    hostKeys = [
      {
        path = "/etc/ssh/host-keys/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/etc/ssh/host-keys/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  # Create host keys directory and generate keys if they don't exist
  systemd.services.generate-ssh-host-keys = {
    description = "Generate SSH host keys if they don't exist";
    before = [ "sshd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /etc/ssh/host-keys

      # Generate ED25519 key if it doesn't exist
      if [ ! -f /etc/ssh/host-keys/ssh_host_ed25519_key ]; then
        echo "Generating SSH ED25519 host key..."
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /etc/ssh/host-keys/ssh_host_ed25519_key -N ""
      fi

      # Generate RSA key if it doesn't exist
      if [ ! -f /etc/ssh/host-keys/ssh_host_rsa_key ]; then
        echo "Generating SSH RSA host key..."
        ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f /etc/ssh/host-keys/ssh_host_rsa_key -N ""
      fi

      # Set proper permissions
      chmod 600 /etc/ssh/host-keys/ssh_host_*_key
      chmod 644 /etc/ssh/host-keys/ssh_host_*_key.pub
      chown root:root /etc/ssh/host-keys/ssh_host_*
    '';
  };

  # Make SSH service depend on key generation
  systemd.services.sshd = {
    after = [ "generate-ssh-host-keys.service" ];
    wants = [ "generate-ssh-host-keys.service" ];
  };

  microvm.volumes = lib.mkBefore [{
    image = "ssh-host-keys.img";
    mountPoint = "/etc/ssh/host-keys";
    size = 64; # Small volume for just keys
    fsType = "ext4";
    autoCreate = true;
  }];

  # Sudo configuration
  security.sudo.wheelNeedsPassword = false;

  # Basic firewall (SSH only by default)
  networking.firewall = {
    enable = lib.mkDefault true;
    allowedTCPPorts = lib.mkDefault [ 22 ];
  };

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

  # Default timezone
  time.timeZone = lib.mkDefault "UTC";

  # Helper to access VM library
  _module.args.vmLib = import ../lib/vm-lib.nix { inherit lib; };

  # All-in-one helper for VM networking setup
  _module.args.mkVMNetworking = { vmTier, vmIndex, extraRoutes ? [ ] }:
    let
      vmLib = import ../lib/vm-lib.nix { inherit lib; };
      vmMAC = vmLib.mkMAC {
        tier = vmTier;
        index = vmIndex;
      };
      vmIP = vmLib.mkIP {
        tier = vmTier;
        index = vmIndex;
      };
    in {
      # Interface configuration
      interfaces = [{
        id = vmLib.mkInterfaceID {
          tier = vmTier;
          index = vmIndex;
        };
        type = "tap";
        mac = vmMAC;
      }];

      # Network configuration  
      networkConfig = {
        matchConfig.MACAddress = vmMAC;
        address = [ "${vmIP}/32" ];

        routes = [
          {
            routeConfig = {
              Destination = "10.0.0.0/32";
              GatewayOnLink = true;
              Metric = 10; # Low metric = high priority
              PreferredSource = vmIP; # This is the key fix!
            };
          }
          {
            routeConfig = {
              Destination = "0.0.0.0/0";
              Gateway = "10.0.0.0";
              GatewayOnLink = true;
              Metric = 10; # Low metric = high priority
              PreferredSource = vmIP; # This is the key fix!
            };
          }
        ] ++ extraRoutes;

        # Add explicit routing policy rules to ensure source selection
        routingPolicyRules = [{
          routingPolicyRuleConfig = {
            From = vmIP;
            Table = "main";
            Priority = 100;
          };
        }];

        networkConfig = { DNS = [ "9.9.9.9" "1.1.1.1" ]; };
      };
    };

  # Essential packages available in all VMs
  environment.systemPackages = with pkgs; [
    htop
    curl
    wget
    git
    nano
    # Add any other packages you want in every VM
  ];

  # Logging configuration
  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=1month
  '';

  # Default state version
  system.stateVersion = lib.mkDefault "25.05";
}
