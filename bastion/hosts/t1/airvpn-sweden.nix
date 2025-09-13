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

  # WireGuard service (main namespace)
  systemd.services.wireguard-simple = {
    description = "WireGuard VPN (main namespace)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };
    
    script = ''
      while [ ! -f /etc/wireguard/wg0.conf ]; do
        echo "Waiting for WireGuard config..."
        sleep 5
      done

      echo "Starting WireGuard in main namespace..."
      ${pkgs.wireguard-tools}/bin/wg-quick up wg0
      echo "✅ WireGuard started"
      
      # Wait for connection to establish
      echo "Waiting for WireGuard handshake..."
      TIMEOUT=60
      ELAPSED=0
      
      while [ $ELAPSED -lt $TIMEOUT ]; do
        if ${pkgs.wireguard-tools}/bin/wg show | grep -q "latest handshake"; then
          echo "✅ WireGuard handshake successful after $ELAPSED seconds"
          echo "VPN IP: $(${pkgs.curl}/bin/curl -s --max-time 10 ifconfig.me || echo 'Failed to get IP')"
          break
        fi
        
        echo "  Waiting for handshake... ($ELAPSED/$TIMEOUT seconds)"
        sleep 5
        ELAPSED=$((ELAPSED + 5))
      done
      
      if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️  No handshake after $TIMEOUT seconds"
        echo "Current WireGuard status:"
        ${pkgs.wireguard-tools}/bin/wg show
        echo "This may indicate connectivity issues to the VPN server"
      fi
    '';
    
    preStop = ''
      ${pkgs.wireguard-tools}/bin/wg-quick down wg0 || true
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
    regular-ip = "curl -s --interface eth0 ifconfig.me 2>/dev/null || echo 'No eth0'";
  };
}
