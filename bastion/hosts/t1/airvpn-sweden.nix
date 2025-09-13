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

  # VPN Kill Switch / Leak Protection
  systemd.services.vpn-killswitch = {
    description = "VPN Kill Switch - Block traffic when VPN is down";
    after = [ "network.target" ];
    before = [ "wireguard-simple.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };

    script = ''
      echo "Setting up VPN kill switch rules..."
      # Extract VPN server IP from WireGuard config
      VPN_SERVER=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {split($3, arr, ":"); print arr[1]}' /etc/wireguard/wg0.conf)

      # Allow local VM traffic (SSH, etc.)
      ${pkgs.iptables}/bin/iptables -I OUTPUT -d 10.0.0.0/16 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -I OUTPUT -d 192.168.0.0/16 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -I OUTPUT -d 127.0.0.0/8 -j ACCEPT

      # Allow VPN server connection
      if [ -n "$VPN_SERVER" ]; then
        echo "Allowing VPN server: $VPN_SERVER"
        ${pkgs.iptables}/bin/iptables -I OUTPUT -d "$VPN_SERVER" -j ACCEPT
      fi

      # Allow traffic through VPN interface (when it exists)
      ${pkgs.iptables}/bin/iptables -I OUTPUT -o wg+ -j ACCEPT

      # Block all other outbound traffic (kill switch)
      ${pkgs.iptables}/bin/iptables -A OUTPUT -j REJECT --reject-with icmp-net-unreachable

      echo "Kill switch enabled - only VPN traffic allowed"
    '';

    preStop = ''
      echo "Removing kill switch rules..."
      VPN_SERVER=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {split($3, arr, ":"); print arr[1]}' /etc/wireguard/wg0.conf)
      ${pkgs.iptables}/bin/iptables -D OUTPUT -d 10.0.0.0/16 -j ACCEPT || true
      ${pkgs.iptables}/bin/iptables -D OUTPUT -d 192.168.0.0/16 -j ACCEPT || true
      ${pkgs.iptables}/bin/iptables -D OUTPUT -d 127.0.0.0/8 -j ACCEPT || true
      ${pkgs.iptables}/bin/iptables -D OUTPUT -d "$VPN_SERVER" -j ACCEPT || true
      ${pkgs.iptables}/bin/iptables -D OUTPUT -o wg+ -j ACCEPT || true
      ${pkgs.iptables}/bin/iptables -D OUTPUT -j REJECT --reject-with icmp-net-unreachable || true
    '';
  };

  # Route management service (runs before WireGuard)
  systemd.services.wireguard-routes = {
    description = "Setup routes for WireGuard";
    after = [ "vpn-killswitch.service" ];
    before = [ "wireguard-simple.service" ];
    wants = [ "vpn-killswitch.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };

    script = ''
      # Discover current network setup
      DEFAULT_IFACE=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $5}' | head -1)
      DEFAULT_GW=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $3}' | head -1)
      # Extract VPN server IP from WireGuard config
      VPN_SERVER=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {split($3, arr, ":"); print arr[1]}' /etc/wireguard/wg0.conf)

      echo "Setting up routes via interface: $DEFAULT_IFACE, gateway: $DEFAULT_GW"

      # Add routes to keep local VM traffic local
      ${pkgs.iproute2}/bin/ip route add 10.0.0.0/24 dev "$DEFAULT_IFACE" metric 1 || true
      ${pkgs.iproute2}/bin/ip route add 10.0.1.0/24 dev "$DEFAULT_IFACE" metric 1 || true

      # Add specific route ONLY for VPN server
      if [ -n "$VPN_SERVER" ]; then
        echo "Adding route for VPN server: $VPN_SERVER"
        ${pkgs.iproute2}/bin/ip route add "$VPN_SERVER" via "$DEFAULT_GW" dev "$DEFAULT_IFACE" metric 1 || true
      fi

      echo "Routes configured successfully"
    '';

    preStop = ''
      # Clean up routes
      DEFAULT_IFACE=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $5}' | head -1)
      DEFAULT_GW=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $3}' | head -1)
      VPN_SERVER=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {split($3, arr, ":"); print arr[1]}' /etc/wireguard/wg0.conf)

      echo "Cleaning up routes"
      ${pkgs.iproute2}/bin/ip route del 10.0.0.0/24 dev "$DEFAULT_IFACE" metric 1 || true
      ${pkgs.iproute2}/bin/ip route del 10.0.1.0/24 dev "$DEFAULT_IFACE" metric 1 || true
      ${pkgs.iproute2}/bin/ip route del "$VPN_SERVER" via "$DEFAULT_GW" dev "$DEFAULT_IFACE" metric 1 || true
    '';
  };

  # WireGuard service (main namespace)
  systemd.services.wireguard-simple = {
    description = "WireGuard VPN (main namespace)";
    after = [ "network.target" "wireguard-routes.service" ];
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
  };
}
