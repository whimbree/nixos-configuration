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

  # TODO: For brittleness mitigation, consider adding some basic monitoring:
  # A systemd timer that periodically checks if the iptables rules are still present
  # Health checks that verify Tailscale connectivity and alert if it degrades
  # Maybe log the output of that routing table check so you can see if routes disappear after a restart
  systemd.services.wg-ns-mss-clamp = {
    description = "MSS clamping for nested tunnels";
    after = [ "wg.service" "tailscaled-wg.service" ];
    requires = [ "wg.service" "tailscaled-wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # MSS (Maximum Segment Size) clamping for Tailscale-over-WireGuard nested tunnels
      #
      # WHY THIS IS NEEDED:
      # When tunneling Tailscale over WireGuard, packets get double-encapsulated with
      # additional headers from both tunnel layers:
      #   - WireGuard overhead reduces 1500 MTU to 1320 (as configured in wg0.conf)
      #     WireGuard adds ~60 bytes (outer IP + UDP + WireGuard crypto headers)
      #   - Tailscale adds ~40 bytes (WireGuard protocol inside Tailscale tunnel)
      #   - Effective MTU: 1280 bytes (tailscale0 interface)
      #
      # Safe MSS calculation:
      #   1280 (effective MTU)
      #   - 40 (IP header, 40 for IPv6)
      #   - 40 (TCP header with options like timestamps, SACK, window scaling)
      #   = 1200 bytes safe MSS
      #
      # Without MSS clamping, TCP tries to send segments based on interface MTU.
      # After adding tunnel headers, these packets exceed the path MTU and get
      # fragmented or silently dropped (if DF bit is set).
      #
      # Path MTU Discovery (PMTUD) should handle this via ICMP "packet too big"
      # messages, but PMTUD fails in nested tunnels because:
      #   1. ICMP messages get lost/blocked in the tunnel layers
      #   2. Multiple encapsulation confuses the discovery process
      #   3. Result: packets silently dropped → TCP retransmits → severe packet loss
      #
      # MSS clamping forces both sides of TCP connections to agree on smaller segment
      # sizes (1200 bytes) during the handshake (SYN/SYN-ACK), preventing oversized
      # packets before they're created.
      #
      # We use --set-mss 1200 instead of --clamp-mss-to-pmtu because the kernel's
      # automatic calculation (1280 - 40 = 1240) doesn't account for the full 80 bytes
      # of TCP/IP overhead. Testing confirmed 1240 causes severe performance degradation
      # (5MB/s → 60KB/s), while 1200 works reliably.
      #
      # THREE RULES for defense in depth:
      #   - PREROUTING: Clamp incoming SYN from Tailscale clients
      #                 Critical for SOCKS proxy, handles most traffic
      #   - OUTPUT: Clamp locally-originated SYN/SYN-ACK packets
      #   - FORWARD: Clamp forwarded traffic for exit node functionality
      #
      # Testing shows PREROUTING alone is sufficient for SOCKS + exit node use cases,
      # but all three rules provide defense in depth at negligible cost.

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

      # Clamp locally-originated SYN-ACK packets
      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT \
        -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --set-mss 1200

      echo "✅ MSS clamping configured (1200 bytes for all chains)"
    '';
  };

  # systemd.services.tailscale-mtu-fix = {
  #   description = "Fix Tailscale MTU for nested VPN";
  #   after = [ "tailscaled-wg.service" ];
  #   requires = [ "tailscaled-wg.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig.Type = "oneshot";
  #   script = ''
  #     # Wait for tailscale0 to exist
  #     for i in {1..30}; do
  #       ${pkgs.iproute2}/bin/ip netns exec wg-ns ip link show tailscale0 2>/dev/null && break
  #       sleep 1
  #     done

  #     # Set MTU accounting for double encapsulation (WG overhead + Tailscale overhead)
  #     ${pkgs.iproute2}/bin/ip netns exec wg-ns ip link set tailscale0 mtu 1280
  #   '';
  # };

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
