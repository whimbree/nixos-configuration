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

  # 1. Create VPN network namespace
  systemd.services.create-vpn-netns = {
    description = "Create VPN network namespace";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${pkgs.iproute2}/bin/ip netns list | grep -q "^vpn$"; then
        ${pkgs.iproute2}/bin/ip netns add vpn
        ${pkgs.iproute2}/bin/ip netns exec vpn
        ${pkgs.iproute2}/bin/ip link set lo up
        echo "Created VPN namespace"
      fi
    '';
    preStop = ''
      ${pkgs.iproute2}/bin/ip netns del vpn || true
    '';
  };

  # 2. Create bridge for VPN namespace connectivity
  systemd.services.setup-vpn-bridge = {
    description = "Bridge VPN namespace to main namespace";
    after = [ "create-vpn-netns.service" "network.target" ];
    wants = [ "create-vpn-netns.service" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "wireguard-vpn.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };

    script = ''
      # Discover current network setup
      DEFAULT_IFACE=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $5}' | head -1)
      DEFAULT_GW=$(${pkgs.iproute2}/bin/ip route show default | ${pkgs.gawk}/bin/awk '{print $3}' | head -1)
      VPN_SERVER=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {split($3, arr, ":"); print arr[1]}' /etc/wireguard/wg0.conf)

      echo "Setting up VPN bridge via interface: $DEFAULT_IFACE, gateway: $DEFAULT_GW"
      echo "VPN server: $VPN_SERVER"

      # Create veth pair for namespace communication
      ${pkgs.iproute2}/bin/ip link add vpn-bridge-main type veth peer name vpn-bridge-vpn

      # Move VPN end to VPN namespace
      ${pkgs.iproute2}/bin/ip link set vpn-bridge-vpn netns vpn

      # Configure main namespace side
      ${pkgs.iproute2}/bin/ip addr add 192.168.200.1/30 dev vpn-bridge-main
      ${pkgs.iproute2}/bin/ip link set vpn-bridge-main up

      # Configure VPN namespace side
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip addr add 192.168.200.2/30 dev vpn-bridge-vpn
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip link set vpn-bridge-vpn up

      # Set up routing in VPN namespace - use your working route logic!
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip route add default via 192.168.200.1 dev vpn-bridge-vpn metric 100

      # Enable NAT for VPN namespace initial connectivity
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 192.168.200.0/30 -j MASQUERADE
      ${pkgs.iptables}/bin/iptables -A FORWARD -i vpn-bridge-main -j ACCEPT
      ${pkgs.iptables}/bin/iptables -A FORWARD -o vpn-bridge-main -j ACCEPT

      echo "✅ VPN bridge established: 192.168.200.1 <-> 192.168.200.2"
    '';

    preStop = ''
      # Clean up iptables rules
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 192.168.200.0/30 -j MASQUERADE 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -i vpn-bridge-main -j ACCEPT 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -o vpn-bridge-main -j ACCEPT 2>/dev/null || true

      # Remove veth pair
      ${pkgs.iproute2}/bin/ip link del vpn-bridge-main 2>/dev/null || true
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
