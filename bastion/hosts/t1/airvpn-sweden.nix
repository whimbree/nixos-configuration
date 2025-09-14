{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };
in {
  microvm = {
    mem = 2048;
    hotplugMem = 2048;
    vcpu = 2;

    # Share VPN config from host
    shares = [
      {
        source = "/services/airvpn-microvm/var/lib/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tailscale";
        proto = "virtiofs";
        securityModel = "none";
      }
      {
        source = "/services/airvpn-microvm/etc/wireguard";
        mountPoint = "/etc/wireguard";
        tag = "wireguard";
        proto = "virtiofs";
        securityModel = "none";
      }
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # Required packages
  environment.systemPackages = with pkgs; [
    wireguard-tools
    tailscale
    iproute2
    iptables
    bind # for nslookup/dig for VPN testing
    iputils # for ping in VPN tests
    curl
    gawk
    dante # SOCKS proxy server
    (writeShellScriptBin "vpn-test" ''
      echo "=== WireGuard Status ==="
      wg show || echo "WireGuard not running"
      echo ""
      echo "=== IP Test ==="
      echo -n "Current IP: "
      curl -s --max-time 5 ifconfig.me || echo "Failed"
      echo ""
      echo "=== Connectivity Test ==="
      ping -c 2 8.8.8.8 && echo "✅ Internet works" || echo "❌ No internet"
    '')
  ];

  # Enable IP forwarding for NAT
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  # Test adding interface manually with script (AFTER networking is stable)
  systemd.services.test-add-interface = {
    description = "Test adding interface manually";
    after = [ "network-debug.service" ];
    # Don't auto-start this - run manually with: systemctl start test-add-interface
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      echo "=== BEFORE ADDING INTERFACE ===" >> /etc/wireguard/network-debug.log
      ${pkgs.iproute2}/bin/ip route show >> /etc/wireguard/network-debug.log
      echo "Default route: $(${pkgs.iproute2}/bin/ip route show default)" >> /etc/wireguard/network-debug.log
      
      ${pkgs.iputils}/bin/ping -c 1 10.0.0.0 >> /etc/wireguard/network-debug.log 2>&1 || echo "PING FAILED BEFORE INTERFACE ADD" >> /etc/wireguard/network-debug.log

      # Add a simple veth pair
      ${pkgs.iproute2}/bin/ip link add veth0 type veth peer name veth1
      
      echo "=== AFTER ADDING INTERFACE ===" >> /etc/wireguard/network-debug.log
      ${pkgs.iproute2}/bin/ip addr show >> /etc/wireguard/network-debug.log
      ${pkgs.iproute2}/bin/ip route show >> /etc/wireguard/network-debug.log
      echo "Default route: $(${pkgs.iproute2}/bin/ip route show default)" >> /etc/wireguard/network-debug.log
      
      # Test if SSH still works (test connectivity to gateway)
      ${pkgs.iputils}/bin/ping -c 1 10.0.0.0 >> /etc/wireguard/network-debug.log 2>&1 || echo "PING FAILED AFTER INTERFACE ADD" >> /etc/wireguard/network-debug.log
    '';
    
    preStop = ''
      ${pkgs.iproute2}/bin/ip link delete veth0 2>/dev/null || true
    '';
  };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH

    ];
  };

  # Helpful aliases
  environment.shellAliases = {
    wg-status = "sudo wg show";
    vpn-ip = "curl -s ifconfig.me";
  };
}
