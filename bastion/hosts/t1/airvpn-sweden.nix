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
    # vsock.cid = vmConfig.tier * 100 + vmConfig.index;
    mem = 2048;
    hotplugMem = 2048;
    vcpu = 4;

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
      {
        source = "/services/airvpn-microvm/var/lib/deluge";
        mountPoint = "/var/lib/deluge";
        tag = "deluge";
        proto = "virtiofs";
        securityModel = "none";
      }
      {
        source = "/ocean/downloads";
        mountPoint = "/downloads";
        tag = "downloads";
        proto = "virtiofs";
        securityModel = "none";
      }
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig // {
    linkConfig.MTUBytes = "1400";
  };

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
    tcpdump
    unbound
    dnsmasq
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
    "net.ipv6.conf.all.disable_ipv6" = 1;
    # Increase TCP buffers for better throughput
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
  };

  systemd.services."netns@" = {
    description = "%I-ns network namespace";
    # Delay network.target until this unit has finished starting up.
    before = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      PrivateNetwork = true;
      ExecStart = "${
          pkgs.writers.writeDash "netns-up" ''
            ${pkgs.iproute2}/bin/ip netns add $1-ns
            ${pkgs.iproute2}/bin/ip netns exec $1-ns ${pkgs.iproute2}/bin/ip link set lo up
          ''
        } %I";
      ExecStop = "${pkgs.iproute2}/bin/ip netns del %I-ns";
      # This is required since systemd commit c2da3bf, shipped in systemd 254.
      # See discussion at https://github.com/systemd/systemd/issues/28686
      PrivateMounts = false;
    };
  };

  systemd.services.wg = {
    description = "wg network interface in isolated namespace";
    # Absolutely require the wg network namespace to exist.
    bindsTo = [ "netns@wg.service" ];
    # Require a network connection.
    requires = [ "network-online.target" "nss-lookup.target" ];
    # Start after and stop before those units.
    after = [ "netns@wg.service" "network-online.target" "nss-lookup.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };

    script = ''
      echo "Setting up WireGuard interface..."

      # Extract configuration from wg0.conf file
      WG_ADDRESS=$(${pkgs.gawk}/bin/awk '/^Address/ {gsub(/Address = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PRIVATE_KEY=$(${pkgs.gawk}/bin/awk '/^PrivateKey/ {gsub(/PrivateKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_MTU=$(${pkgs.gawk}/bin/awk '/^MTU/ {gsub(/MTU = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_DNS=$(${pkgs.gawk}/bin/awk '/^DNS/ {gsub(/DNS = /, ""); print}' /etc/wireguard/wg0.conf)

      WG_PUBLIC_KEY=$(${pkgs.gawk}/bin/awk '/^PublicKey/ {gsub(/PublicKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PRESHARED_KEY=$(${pkgs.gawk}/bin/awk '/^PresharedKey/ {gsub(/PresharedKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_ENDPOINT=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {gsub(/Endpoint = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PERSISTENT_KEEPALIVE=$(${pkgs.gawk}/bin/awk '/^PersistentKeepalive/ {gsub(/PersistentKeepalive = /, ""); print}' /etc/wireguard/wg0.conf)

      echo "Config extracted: Address=$WG_ADDRESS, MTU=$WG_MTU, Endpoint=$WG_ENDPOINT"

      # Step 1: Create WireGuard interface in main namespace (where it can reach internet)
      ${pkgs.iproute2}/bin/ip link add wg0 type wireguard

      # Step 2: Set MTU before configuring crypto (important for some networks)
      ${pkgs.iproute2}/bin/ip link set wg0 mtu $WG_MTU

      # Step 3: Configure WireGuard crypto and peer settings in main namespace
      # This allows the handshake to happen while interface can reach VPN server
      ${pkgs.wireguard-tools}/bin/wg set wg0 \
        private-key <(echo "$WG_PRIVATE_KEY") \
        peer "$WG_PUBLIC_KEY" \
        preshared-key <(echo "$WG_PRESHARED_KEY") \
        allowed-ips 0.0.0.0/0 \
        endpoint "$WG_ENDPOINT" \
        persistent-keepalive "$WG_PERSISTENT_KEEPALIVE"

      # todo: explain why this works
      # Step 4: Move to namespace BEFORE adding IP/routes
      ${pkgs.iproute2}/bin/ip link set wg0 netns wg-ns up

      # Step 5: Configure routes
      # Route for IP address inside the isolated namespace
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip addr add $WG_ADDRESS dev wg0
      # Route for all traffic to go through wg0
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add default dev wg0

      # Step 6: Configure DNS inside the namespace
      # Dnsmasq with TTL control
      # ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.dnsmasq}/bin/dnsmasq \
      #   --no-daemon \
      #   --pid-file=/tmp/dnsmasq-wg.pid \
      #   --server=$WG_DNS \
      #   --cache-size=10000 \
      #   --min-cache-ttl=300 \
      #   --max-cache-ttl=86400 \
      #   --listen-address=127.0.0.1 \
      #   --port=53 \
      #   --no-resolv &
      # ${pkgs.coreutils}/bin/mkdir -p /etc/netns/wg-ns
      # echo "nameserver 127.0.0.1" > /etc/netns/wg-ns/resolv.conf

      echo "✅ WireGuard interface moved to vpn namespace and configured"

      # Step 7: Wait for WireGuard connection to establish (with retry loop)
      echo "Waiting for WireGuard handshake..."
      ATTEMPTS=0
      MAX_ATTEMPTS=30  # 5 minutes with 10-second intervals

      while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.wireguard-tools}/bin/wg show | grep -q "latest handshake"; then
          VPN_IP=$(${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.curl}/bin/curl -s --max-time 10 ifconfig.me || echo "Failed")
          echo "✅ WireGuard handshake successful after $((ATTEMPTS * 10)) seconds, VPN IP: $VPN_IP"
          break
        else
          ATTEMPTS=$((ATTEMPTS + 1))
          echo "⚠️  Attempt $ATTEMPTS/$MAX_ATTEMPTS: No handshake yet, retrying in 10 seconds..."
          if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
            echo "❌ WireGuard handshake failed after $((MAX_ATTEMPTS * 10)) seconds"
            echo "Current WireGuard status:"
            ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.wireguard-tools}/bin/wg show
            echo "Check configuration, endpoint reachability, and firewall settings"
            exit 1
          fi
          sleep 10
        fi
      done
    '';

    preStop = ''
      if [ -f /tmp/dnsmasq-wg.pid ]; then
        echo "Cleaning up dnsmasq..."
        kill $(cat /tmp/dnsmasq-wg.pid) 2>/dev/null || true
        rm -f /tmp/dnsmasq-wg.pid
      fi

      echo "Cleaning up wg0 interface..."
      # Remove interface from wg-ns namespace (this also brings it down)
      ${pkgs.iproute2}/bin/ip -n wg-ns link del wg0 || true
    '';
  };

  systemd.services.dnsmasq-wg = {
    description = "Dnsmasq for WireGuard namespace";
    after = [ "wg.service" ];
    requires = [ "wg.service" ];
    wantedBy = [ "multi-user.target" ];

    preStart = ''
      ${pkgs.coreutils}/bin/mkdir -p /etc/netns/wg-ns
      echo "nameserver 127.0.0.1" > /etc/netns/wg-ns/resolv.conf
    '';

    serviceConfig = {
      Type = "simple"; # Changed from forking since we use --no-daemon
      NetworkNamespacePath = "/var/run/netns/wg-ns";
      ExecStart = ''
        ${pkgs.dnsmasq}/bin/dnsmasq \
          --no-daemon \
          --pid-file=/run/dnsmasq-wg.pid \
          --server=10.128.0.1 \
          --cache-size=10000 \
          --min-cache-ttl=300 \
          --max-cache-ttl=86400 \
          --listen-address=127.0.0.1 \
          --port=53 \
          --no-resolv
      '';
      Restart = "always";
    };
  };

  services.deluge = {
    enable = true;
    web = {
      enable = true;
      port = 8112;
    };
  };

  # binding deluged to network namespace
  systemd.services.deluged.bindsTo = [ "netns@wg.service" ];
  systemd.services.deluged.requires = [ "network-online.target" "wg.service" ];
  systemd.services.deluged.after = [ "wg.service" ];
  # systemd.services.deluged.serviceConfig.NetworkNamespacePath =
  #   [ "/var/run/netns/wg-ns" ];
  systemd.services.deluged.serviceConfig.NetworkNamespacePath =
    "/var/run/netns/wg-ns";

  # allowing delugeweb to access deluged in network namespace, a socket is necesarry
  systemd.sockets."proxy-to-deluged" = {
    enable = true;
    description = "Socket for Proxy to Deluge Daemon";
    listenStreams = [ "58846" ];
    wantedBy = [ "sockets.target" ];
  };

  # creating proxy service on socket, which forwards the same port from the root namespace to the isolated namespace
  systemd.services."proxy-to-deluged" = {
    enable = true;
    description = "Proxy to Deluge Daemon in Network Namespace";
    requires = [ "deluged.service" "proxy-to-deluged.socket" ];
    after = [ "deluged.service" "proxy-to-deluged.socket" ];
    unitConfig = { JoinsNamespaceOf = "deluged.service"; };
    serviceConfig = {
      User = "deluge";
      Group = "deluge";
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=5min 127.0.0.1:58846";
      PrivateNetwork = "yes";
    };
  };

  services.tailscale.enable = false;

  systemd.services.tailscaled-wg = {
    description = "Tailscale in WireGuard namespace";
    bindsTo = [ "netns@wg.service" ];
    after = [ "wg.service" "dnsmasq-wg.service" ];
    requires = [ "wg.service" "dnsmasq-wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      # NixOS makes /etc/resolv.conf a symlink to /run/systemd/resolve/stub-resolv.conf
      # We need to bind-mount over the actual file (not the symlink) so tailscaled
      # sees dnsmasq (127.0.0.1) instead of systemd-resolved (127.0.0.53)
      # This mount happens in an isolated mount namespace, so the host is unaffected
      ExecStart =
        "${pkgs.util-linux}/bin/unshare --mount ${pkgs.bash}/bin/bash -c '${pkgs.util-linux}/bin/mount --bind /etc/netns/wg-ns/resolv.conf /run/systemd/resolve/stub-resolv.conf && exec ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --no-logs-no-support'";
      # ExecStart = "${pkgs.util-linux}/bin/unshare --mount ${pkgs.bash}/bin/bash -c '${pkgs.util-linux}/bin/mount --bind /etc/netns/wg-ns/resolv.conf /run/systemd/resolve/stub-resolv.conf && exec ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --no-logs-no-support --tun=userspace-networking'";
      Restart = "always";
    };

    environment = { TS_NO_LOGS_NO_SUPPORT = "true"; };
  };

  systemd.services.wg-external-interface = {
    description = "Add external interface to wg-ns for Tailscale mesh";
    after = [ "netns@wg.service" "network-online.target" ];
    requires = [ "netns@wg.service" "network-online.target" ];
    before = [ "wg.service" ]; # BEFORE wg, so routes are correct
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Create macvlan for local network access
      ${pkgs.iproute2}/bin/ip link add mvlan0 link ens4 type macvlan mode bridge
      ${pkgs.iproute2}/bin/ip link set mvlan0 netns wg-ns
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip addr add 10.0.1.20/24 dev mvlan0
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip link set mvlan0 up
    '';
  };

  # Fix routing AFTER wg sets up wg0
  # systemd.services.wg-routing-fix = {
  # description = "Add LAN routes like Docker LAN_NETWORK";
  # after = [ "wg.service" "wg-external-interface.service" ];
  # requires = [ "wg.service" "wg-external-interface.service" ];
  # wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };

  #   script = ''
  #     # Default through wg0 is already set by wg.service - keep it

  #     # Add specific routes to exclude from VPN
  #     ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add 100.64.0.0/10 dev mvlan0 // tailscale
  #     ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add 10.0.1.0/24 dev mvlan0 // microvms
  #     ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add 172.17.0.0/12 dev mvlan0 // docker
  #   '';
  # };

  # TODO: For brittleness mitigation, consider adding some basic monitoring:
  # A systemd timer that periodically checks if the iptables rules are still present
  # Health checks that verify Tailscale connectivity and alert if it degrades
  # Maybe log the output of that routing table check so you can see if routes disappear after a restart
  systemd.services.wg-ns-mss-clamp = {
    description = "MSS clamping for nested tunnels";
    after = [ "wg.service" "tailscaled-wg.service" ];
    requires = [ "wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # MSS (Maximum Segment Size) clamping for Tailscale-over-WireGuard nested tunnels
      #
      # WHY THIS IS NEEDED:
      # When tunneling Tailscale (userspace or kernel) over WireGuard, packets get
      # double-encapsulated with additional headers:
      #   - WireGuard adds ~60 bytes (outer IP + UDP + WireGuard crypto headers)
      #   - Tailscale adds ~40 bytes (WireGuard protocol inside Tailscale tunnel)
      #   - Total overhead: ~100 bytes
      #
      # Standard Ethernet MTU is 1500 bytes. After WireGuard (1500-60=1440) and
      # Tailscale (1440-40=1400), effective MTU is only 1400 bytes.
      #
      # Without MSS clamping, TCP tries to send 1460-byte segments (standard for 1500 MTU).
      # After adding both tunnel headers, these become 1560+ byte packets, which exceed
      # the physical MTU and get fragmented or silently dropped (if DF bit is set).
      #
      # Path MTU Discovery (PMTUD) should handle this automatically via ICMP "packet too big"
      # messages, but PMTUD fails in nested tunnels because:
      #   1. ICMP messages get lost/blocked in the tunnel layers
      #   2. Multiple encapsulation confuses the discovery process
      #   3. Result: packets silently dropped → TCP retransmits forever → 28% packet loss
      #
      # MSS clamping forces both sides of TCP connections to agree on smaller segment sizes
      # (1200 bytes) during the handshake (SYN/SYN-ACK), preventing oversized packets.
      #
      # THREE RULES NEEDED (not just one):
      #   - PREROUTING: Clamp incoming SYN from Tailscale clients (critical for SOCKS)
      #   - OUTPUT: Clamp outgoing SYN-ACK from local services (SOCKS server replies)
      #   - FORWARD: Clamp forwarded traffic (exit node functionality)
      #
      # Without PREROUTING, clients propose MSS=1228 (from tailscale0 MTU 1280), server
      # accepts it, and packets get fragmented/dropped. With PREROUTING, clients are forced
      # to MSS=1200 during handshake, preventing the issue.

      # Clamp incoming SYN packets from Tailscale clients
      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A PREROUTING \
        -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --set-mss 1200

      # Clamp forwarded traffic (for exit node functionality)
      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD \
        -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --set-mss 1200

      # Clamp locally-originated SYN-ACK packets (SOCKS server replies)
      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT \
        -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --set-mss 1200
        
      echo "✅ MSS clamping configured (1200 bytes accounting for ~100 byte double-tunnel overhead)"
    '';
  };

  systemd.services.wg-routing-fix = {
    description = "Add LAN routes like Docker LAN_NETWORK";
    after = [ "wg.service" "wg-external-interface.service" ];
    requires = [ "wg.service" "wg-external-interface.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Keep local traffic local (don't send through VPN)
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add 10.0.1.0/24 dev mvlan0 2>/dev/null || true    # microvms
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add 172.17.0.0/12 dev mvlan0 2>/dev/null || true  # docker

      # Remove the Tailscale route - let Tailscale manage its own routing
      # (The 100.64.0.0/10 route was breaking return traffic)

      echo "✅ LAN routing configured (10.0.1.0/24, 172.17.0.0/12)"
      echo "Current routing table in wg-ns:"
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route show
    '';
  };

  systemd.services.tailscale-mtu-fix = {
    description = "Fix Tailscale MTU for nested VPN";
    after = [ "tailscaled-wg.service" ];
    requires = [ "tailscaled-wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig.Type = "oneshot";
    script = ''
      # Wait for tailscale0 to exist
      for i in {1..30}; do
        ${pkgs.iproute2}/bin/ip netns exec wg-ns ip link show tailscale0 2>/dev/null && break
        sleep 1
      done

      # Set MTU accounting for double encapsulation (WG overhead + Tailscale overhead)
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ip link set tailscale0 mtu 1280
    '';
  };

  systemd.services.sockd = {
    description = "microsocks SOCKS5 proxy";
    after = [ "wg.service" ];
    requires = [ "wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
      ExecStart = "${pkgs.microsocks}/bin/microsocks -i 0.0.0.0 -p 1080";
    };
  };

  # systemd.services.sockd = {
  #   description = "Dante SOCKS proxy in VPN namespace";
  #   after = [ "wg.service" ];
  #   requires = [ "wg.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "simple";
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";
  #     ExecStart = "${pkgs.dante}/bin/sockd -f ${
  #         pkgs.writeText "sockd.conf" ''
  #           logoutput: syslog
  #           internal: 0.0.0.0 port = 1080
  #           external: wg0

  #           clientmethod: none
  #           socksmethod: none

  #           client pass {
  #             from: 0.0.0.0/0 to: 0.0.0.0/0
  #           }

  #           socks pass {
  #             from: 0.0.0.0/0 to: 0.0.0.0/0
  #             protocol: tcp udp
  #           }
  #         ''
  #       }";
  #   };
  # };

  # Add socket for proxying
  systemd.sockets."proxy-to-sockd" = {
    enable = true;
    description = "Socket for Proxy to SOCKS Daemon";
    listenStreams = [ "1080" ];
    wantedBy = [ "sockets.target" ];
  };

  # Proxy service
  systemd.services."proxy-to-sockd" = {
    enable = true;
    description = "Proxy to SOCKS Daemon in Network Namespace";
    requires = [ "sockd.service" "proxy-to-sockd.socket" ];
    after = [ "sockd.service" "proxy-to-sockd.socket" ];
    unitConfig = { JoinsNamespaceOf = "sockd.service"; };
    serviceConfig = {
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:1080";
      PrivateNetwork = "yes";
    };
  };

  # Run tailscaled in the VPN namespace
  # systemd.services.tailscaled = {
  #   bindsTo = [ "netns@wg.service" ];
  #   requires = [ "wg.service" "dnsmasq-wg.service" ];
  #   after = [ "wg.service" "dnsmasq-wg.service"];

  #   serviceConfig = {
  #     # Run in the VPN namespace
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";

  #     # override the environment to tell tailscaled about DNS
  #     Environment = [
  #       "TS_DNS_MODE=nochange"  # Don't manage DNS
  #     ];

  #     # Wait longer for VPN to be ready
  #     RestartSec = "10s";
  #   };

  #   preStart = ''
  #     # Ensure the namespace resolv.conf exists
  #     mkdir -p /etc/netns/wg-ns
  #     echo "nameserver 127.0.0.1" > /etc/netns/wg-ns/resolv.conf
  #   '';
  # };

  # # Helper service to authenticate Tailscale (run once)
  # systemd.services.tailscale-auth = {
  #   description = "Authenticate Tailscale through VPN";
  #   after = [ "tailscaled.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #   };

  #   script = ''
  #     # Wait for tailscaled to be ready
  #     sleep 5

  #     # Check if already authenticated
  #     if ! ${pkgs.iproute2}/bin/ip netns exec wg-ns \
  #          ${pkgs.tailscale}/bin/tailscale status &>/dev/null; then

  #       echo "Tailscale needs authentication. Run:"
  #       echo "  sudo ip netns exec wg-ns tailscale up"
  #       echo "Or with auth key:"
  #       echo "  sudo ip netns exec wg-ns tailscale up --authkey=YOUR_KEY"
  #     fi
  #   '';
  # };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH
      1080 # SOCKS proxy
      8112
      5201
    ];
  };

  # Helpful aliases
  environment.shellAliases = {
    wg-status = "sudo ip netns exec wg-ns wg show";
    vpn-ip = "sudo ip netns exec wg-ns curl -s ifconfig.me";
    real-ip = "curl -s ifconfig.me";
  };
}
