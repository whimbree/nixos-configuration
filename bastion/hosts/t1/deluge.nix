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
      source = "/services/arr/deluge/wireguard";
      mountPoint = "/vpn-configs";
      tag = "vpn-configs";
      proto = "virtiofs";
      securityModel = "none";
    }];

    # Persistent storage for deluge data
    volumes = [
      {
        image = "${vmConfig.hostname}-deluge-data.img";
        mountPoint = "/var/lib/deluge";
        size = 10240; # 10GB for deluge data
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "${vmConfig.hostname}-downloads.img";
        mountPoint = "/downloads";
        size = 51200; # 50GB for downloads
        fsType = "ext4";
        autoCreate = true;
      }
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # Required packages
  environment.systemPackages = with pkgs; [
    wireguard-tools
    iproute2
    iptables
    iputils # for ping in VPN tests
  ];

  # Deluge configuration
  services.deluge = {
    enable = true;
    web = {
      enable = true;
      port = 8112;
    };
    config = {
      download_location = "/downloads";
      listen_ports = [ 46278 46278 ];
      random_port = false;
      # Bind to all interfaces so it can receive external connections
      listen_interface = "0.0.0.0";
    };
  };

  # Users and groups for deluge
  users.users.deluge = {
    isSystemUser = true;
    group = "deluge";
    home = "/var/lib/deluge";
    createHome = true;
  };
  users.groups.deluge = { };

  # Create network namespace
  systemd.services."netns@" = {
    description = "%I network namespace";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip netns add %I";
      ExecStop = "${pkgs.iproute2}/bin/ip netns del %I";
    };
  };

  # VPN Kill Switch - isolated to VPN namespace only
  systemd.services.vpn-killswitch = {
    description = "VPN Kill Switch - Block all traffic except VPN";
    bindsTo = [ "netns@vpn.service" ];
    after = [ "netns@vpn.service" "network-online.target" ];
    # Don't put "before" anything - let main networking establish first
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writers.writeBash "setup-killswitch" ''
        # Set up kill switch rules in VPN namespace ONLY
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -F
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -X

        # Default policies: DROP everything in VPN namespace
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P INPUT DROP
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P FORWARD DROP
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P OUTPUT DROP

        # Allow loopback in VPN namespace
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -i lo -j ACCEPT
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -o lo -j ACCEPT

        # Allow established connections in VPN namespace
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

        # CRITICAL: Allow traffic to VPN server (before tunnel exists)
        VPN_SERVER=$(grep "^Endpoint" /vpn-configs/wg0.conf | cut -d'=' -f2 | cut -d':' -f1 | tr -d ' ')
        VPN_PORT=$(grep "^Endpoint" /vpn-configs/wg0.conf | cut -d':' -f2)
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -d $VPN_SERVER -p udp --dport $VPN_PORT -j ACCEPT

        # Allow traffic through VPN tunnel (after tunnel exists)
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -i wg0 -j ACCEPT
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -o wg0 -j ACCEPT

        # Log dropped packets for debugging (optional)
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -j LOG --log-prefix "VPN-KILLSWITCH-DROP: " --log-level 4
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -j DROP

        echo "VPN kill switch activated in VPN namespace - allowing VPN server: $VPN_SERVER:$VPN_PORT"
      '';

      ExecStop = pkgs.writers.writeBash "teardown-killswitch" ''
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P INPUT ACCEPT 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P FORWARD ACCEPT 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P OUTPUT ACCEPT 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -F 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -X 2>/dev/null || true
      '';
    };
  };

  # systemd.services.wg-vpn-test = {
  #   description = "WireGuard test with config";
  #   bindsTo = [ "netns@vpn.service" ];
  #   after = [ "netns@vpn.service" "vpn-killswitch.service" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #     ExecStart = pkgs.writers.writeBash "wg-test" ''
  #       set -e
  #       echo "Setting up WireGuard interface with config..."

  #       # Create interface
  #       ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
  #       ${pkgs.iproute2}/bin/ip link set wg0 netns vpn

  #       # Configure IP
  #       VPN_IP=$(grep "^Address" /vpn-configs/wg0.conf | cut -d'=' -f2 | tr -d ' ')
  #       ${pkgs.iproute2}/bin/ip -n vpn address add $VPN_IP dev wg0

  #       # Apply WireGuard config
  #       ${pkgs.iproute2}/bin/ip netns exec vpn \
  #         ${pkgs.wireguard-tools}/bin/wg setconf wg0 /vpn-configs/wg0.conf

  #       # Bring up interface
  #       ${pkgs.iproute2}/bin/ip -n vpn link set lo up
  #       ${pkgs.iproute2}/bin/ip -n vpn link set wg0 up

  #       echo "WireGuard configured and up"
  #     '';

  #     ExecStop = pkgs.writers.writeBash "wg-test-stop" ''
  #       ${pkgs.iproute2}/bin/ip -n vpn link del wg0 2>/dev/null || true
  #     '';
  #   };
  # };

  # WireGuard setup in network namespace
  systemd.services.wg-vpn = {
    description = "WireGuard VPN in network namespace";
    bindsTo = [ "netns@vpn.service" ];
    requires = [
      "network-online.target"
      "vpn-killswitch.service"
      "systemd-networkd.service"
    ];
    after = [
      "netns@vpn.service"
      "network-online.target"
      "vpn-killswitch.service"
      "systemd-networkd.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writers.writeBash "wg-up" ''
        set -e

        # Kill switch is already active, blocking all traffic

        # Create WireGuard interface
        ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
        ${pkgs.iproute2}/bin/ip link set wg0 netns vpn

        # Configure VPN IP
        VPN_IP=$(grep "^Address" /vpn-configs/wg0.conf | cut -d'=' -f2 | tr -d ' ')
        ${pkgs.iproute2}/bin/ip -n vpn address add $VPN_IP dev wg0

        # Set WireGuard config
        ${pkgs.iproute2}/bin/ip netns exec vpn \
          ${pkgs.wireguard-tools}/bin/wg setconf wg0 <(grep -A 10 "^\[Peer\]" /vpn-configs/wg0.conf)

        # Bring up interfaces
        ${pkgs.iproute2}/bin/ip -n vpn link set lo up
        ${pkgs.iproute2}/bin/ip -n vpn link set wg0 up

        # Add specific route to VPN server through main network
        # We need to reach the main network gateway from VPN namespace
        VPN_SERVER=$(grep "^Endpoint" /vpn-configs/wg0.conf | cut -d'=' -f2 | cut -d':' -f1 | tr -d ' ')
        ${pkgs.iproute2}/bin/ip -n vpn route add $VPN_SERVER via 10.0.0.0

        # Set default route through VPN
        ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg0

        # Add DNS (optional)
        mkdir -p /etc/netns/vpn
        echo "nameserver 9.9.9.9" > /etc/netns/vpn/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/netns/vpn/resolv.conf

        # Test VPN connectivity
        echo "Testing VPN connectivity..."
        if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c 3 -W 10 9.9.9.9; then
          echo "VPN is working - traffic now allowed through wg0"
        else
          echo "VPN connectivity test failed!"
          exit 1
        fi
      '';

      ExecStop = pkgs.writers.writeBash "wg-down" ''
        ${pkgs.iproute2}/bin/ip -n vpn route del default dev wg0 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip -n vpn link del wg0 2>/dev/null || true
        rm -f /etc/netns/vpn/resolv.conf
        echo "VPN down - kill switch will block all traffic"
      '';
    };
  };

  # # WireGuard setup in network namespace
  # systemd.services.wg-vpn = {
  #   description = "WireGuard VPN in network namespace";
  #   bindsTo = [ "netns@vpn.service" ];
  #   requires = [ "network-online.target" "vpn-killswitch.service" ];
  #   after =
  #     [ "netns@vpn.service" "network-online.target" "vpn-killswitch.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #     ExecStart = pkgs.writers.writeBash "wg-up" ''
  #       set -e

  #       # Create WireGuard interface
  #       ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
  #       ${pkgs.iproute2}/bin/ip link set wg0 netns vpn

  #       # Configure VPN IP
  #       VPN_IP=$(grep "^Address" /vpn-configs/wg0.conf | cut -d'=' -f2 | tr -d ' ')
  #       ${pkgs.iproute2}/bin/ip -n vpn address add $VPN_IP dev wg0

  #       # Set WireGuard config
  #       ${pkgs.iproute2}/bin/ip netns exec vpn \
  #         ${pkgs.wireguard-tools}/bin/wg setconf wg0 /vpn-configs/wg0.conf

  #       # Bring up interfaces
  #       ${pkgs.iproute2}/bin/ip -n vpn link set lo up
  #       ${pkgs.iproute2}/bin/ip -n vpn link set wg0 up

  #       # Set default route through VPN
  #       ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg0

  #       # Add DNS
  #       mkdir -p /etc/netns/vpn
  #       echo "nameserver 9.9.9.9" > /etc/netns/vpn/resolv.conf
  #       echo "nameserver 1.1.1.1" >> /etc/netns/vpn/resolv.conf

  #       # Allow VPN traffic through kill switch
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -i wg0 -j ACCEPT
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -o wg0 -j ACCEPT

  #       # Test VPN connectivity
  #       echo "Testing VPN connectivity..."
  #       if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c 3 -W 10 9.9.9.9; then
  #         echo "VPN is working!"
  #       else
  #         echo "VPN connectivity test failed!"
  #         exit 1
  #       fi
  #     '';

  #     ExecStop = pkgs.writers.writeBash "wg-down" ''
  #       ${pkgs.iproute2}/bin/ip -n vpn route del default dev wg0 2>/dev/null || true
  #       ${pkgs.iproute2}/bin/ip -n vpn link del wg0 2>/dev/null || true
  #       rm -f /etc/netns/vpn/resolv.conf
  #     '';
  #   };
  # };

  # # Run deluge daemon in VPN namespace
  # systemd.services.deluged = {
  #   bindsTo = [ "netns@vpn.service" "wg-vpn.service" ];
  #   requires = [ "wg-vpn.service" "vpn-killswitch.service" ];
  #   after = [ "wg-vpn.service" "vpn-killswitch.service" ];

  #   serviceConfig = {
  #     NetworkNamespacePath = "/var/run/netns/vpn";
  #     # Ensure deluge can access its data
  #     BindPaths = [ "/var/lib/deluge" "/downloads" ];
  #   };

  #   # Override deluge config to bind to VPN interface
  #   environment = { DELUGE_CONFIG_DIR = "/var/lib/deluge/.config/deluge"; };
  # };

  # # Proxy socket for deluge web to communicate with daemon
  # systemd.sockets."proxy-to-deluged" = {
  #   enable = true;
  #   description = "Socket for Proxy to Deluge Daemon";
  #   listenStreams = [ "127.0.0.1:58846" ];
  #   wantedBy = [ "sockets.target" ];
  # };

  # # Proxy service to bridge namespaces
  # systemd.services."proxy-to-deluged" = {
  #   enable = true;
  #   description = "Proxy to Deluge Daemon in VPN namespace";
  #   requires = [ "deluged.service" "proxy-to-deluged.socket" ];
  #   after = [ "deluged.service" "proxy-to-deluged.socket" ];

  #   unitConfig = { JoinsNamespaceOf = "deluged.service"; };

  #   serviceConfig = {
  #     User = "deluge";
  #     Group = "deluge";
  #     ExecStart =
  #       "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=5min 127.0.0.1:58846";
  #     PrivateNetwork = true;
  #   };
  # };

  # # Ensure deluge web can reach the proxied daemon
  # systemd.services.deluge-web = {
  #   after = [ "proxy-to-deluged.service" ];
  #   requires = [ "proxy-to-deluged.service" ];

  #   # Override default daemon connection
  #   environment = { DELUGE_CONFIG_DIR = "/var/lib/deluge/.config/deluge"; };
  # };

  # # Create deluge directories with proper permissions
  # systemd.tmpfiles.rules = [
  #   "d /var/lib/deluge 0755 deluge deluge -"
  #   "d /var/lib/deluge/.config 0755 deluge deluge -"
  #   "d /var/lib/deluge/.config/deluge 0755 deluge deluge -"
  #   "d /downloads 0755 deluge deluge -"
  # ];

  # # Instant VPN kill switch using iptables
  # systemd.services.vpn-killswitch = {
  #   description = "VPN Kill Switch - Block all traffic except VPN";
  #   bindsTo = [ "netns@vpn.service" ];
  #   after = [
  #     "netns@vpn.service"
  #     "systemd-networkd.service"
  #   ]; # Must wait for namespace to exist
  #   before = [ "wg-vpn.service" "deluged.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #     ExecStart = pkgs.writers.writeBash "setup-killswitch" ''
  #       # Set up kill switch rules in VPN namespace
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -F
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -X

  #       # Default policies: DROP everything
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P INPUT DROP
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P FORWARD DROP
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P OUTPUT DROP

  #       # Allow loopback (essential for local communication)
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -i lo -j ACCEPT
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -o lo -j ACCEPT

  #       # Allow established and related connections
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

  #       # CRITICAL: Only allow traffic through VPN interface
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A INPUT -i wg0 -j ACCEPT
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -o wg0 -j ACCEPT

  #       # Allow VPN handshake traffic (before VPN is up)
  #       VPN_HANDSHAKE_PORT=$(grep "^Endpoint" /vpn-configs/wg0.conf | cut -d':' -f2)
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -p udp --dport $VPN_HANDSHAKE_PORT -j ACCEPT

  #       # Log dropped packets for debugging (optional)
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -j LOG --log-prefix "VPN-KILLSWITCH-DROP: " --log-level 4
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -A OUTPUT -j DROP

  #       echo "VPN kill switch activated - all traffic blocked except VPN"
  #     '';

  #     ExecStop = pkgs.writers.writeBash "teardown-killswitch" ''
  #       # Reset iptables in VPN namespace
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P INPUT ACCEPT 2>/dev/null || true
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P FORWARD ACCEPT 2>/dev/null || true
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -P OUTPUT ACCEPT 2>/dev/null || true
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -F 2>/dev/null || true
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iptables}/bin/iptables -X 2>/dev/null || true
  #     '';
  #   };
  # };

  # # Monitor service to restart deluge if VPN fails (secondary protection)
  # systemd.services.vpn-monitor = {
  #   description = "VPN Monitor - Restart services on VPN failure";
  #   after = [ "wg-vpn.service" "vpn-killswitch.service" ];
  #   requires = [ "vpn-killswitch.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "simple";
  #     Restart = "always";
  #     RestartSec = 10;
  #     ExecStart = pkgs.writers.writeBash "vpn-monitor" ''
  #       while true; do
  #         # Check if VPN interface exists and has connectivity
  #         if ! ${pkgs.iproute2}/bin/ip netns exec vpn ip addr show wg0 | grep -q "inet" 2>/dev/null; then
  #           echo "VPN interface down! Restarting VPN services..."
  #           systemctl restart wg-vpn
  #           sleep 30
  #         fi

  #         # Test actual VPN connectivity
  #         if ! ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iputils}/bin/ping -c 1 -W 5 9.9.9.9 >/dev/null 2>&1; then
  #           echo "VPN connectivity lost! Restarting VPN..."
  #           systemctl restart wg-vpn
  #           sleep 30
  #         fi

  #         sleep 10
  #       done
  #     '';
  #   };
  # };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH
      8112 # Deluge web UI
    ];
    # Optionally allow deluge daemon port if needed externally
    # allowedTCPPorts = [ 58846 ]; # Deluge daemon
  };
}
