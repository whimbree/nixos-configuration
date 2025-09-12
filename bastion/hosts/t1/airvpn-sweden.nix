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
    shares = [{
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
    }];
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
    dante # SOCKS proxy server
  ];

  # Enable IP forwarding for NAT
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.forwarding" = 1;
  };

  # 1. Create VPN network namespace
  systemd.services.create-vpn-netns = {
    description = "Create VPN network namespace";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Create namespace if it doesn't exist
      if ! ${pkgs.iproute2}/bin/ip netns list | grep -q "^vpn$"; then
        ${pkgs.iproute2}/bin/ip netns add vpn
        echo "Created VPN network namespace"
      fi

      # Set up loopback in namespace
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip link set lo up
    '';
    preStop = ''
      # Clean up namespace
      ${pkgs.iproute2}/bin/ip netns del vpn || true
    '';
  };

  # 2. WireGuard in VPN namespace
  systemd.services.wireguard-vpn = {
    description = "WireGuard VPN in network namespace";
    after = [ "network.target" "create-vpn-netns.service" ];
    wants = [ "create-vpn-netns.service" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Restart = "on-failure";
      RestartSec = "30s";
    };
    
    script = ''
      while [ ! -f /etc/wireguard/wg0.conf ]; do
        echo "Waiting for WireGuard config..."
        sleep 5
      done

      echo "Starting WireGuard in VPN namespace..."
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.wireguard-tools}/bin/wg-quick up wg0
      echo "✅ WireGuard up in VPN namespace"
    '';
    
    preStop = ''
      # Bring down WireGuard interface
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.wireguard-tools}/bin/wg-quick down wg0 || true
    '';
  };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH

    ];
    # Optionally allow deluge daemon port if needed externally
    # allowedTCPPorts = [ 58846 ]; # Deluge daemon
  };
}
