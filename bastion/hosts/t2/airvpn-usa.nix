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
        source = "/microvms/airvpn-usa/var/lib/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tailscale";
        proto = "virtiofs";
        securityModel = "none";
      }
      {
        source = "/microvms/airvpn-usa/etc/wireguard";
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
    ethtool
    iptables
    gawk
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

  # Disable nscd (Name Service Cache Daemon) to prevent DNS leaks in the VPN namespace.
  #
  # THE PROBLEM:
  # nscd caches DNS lookups at the system level via /var/run/nscd/socket. This socket
  # exists in the MOUNT namespace (not network namespace), so processes in wg-ns can
  # access it. When apps in wg-ns query DNS:
  #   1. glibc checks if /var/run/nscd/socket exists
  #   2. Connects to nscd (running in ROOT namespace)
  #   3. nscd reads ROOT's /etc/nsswitch.conf
  #   4. nscd queries systemd-resolved in ROOT namespace
  #   5. DNS leaks to Cloudflare, completely bypassing our VPN DNS setup
  #
  # THE SOLUTION:
  # Disabling nscd prevents cross-namespace DNS contamination. However, NixOS requires
  # us to also disable NSS modules when nscd is disabled. This is fine - without NSS
  # modules, glibc falls back to classic behavior: directly reading /etc/resolv.conf.
  #
  # RESULT:
  # - Root namespace: /etc/resolv.conf → 127.0.0.53 → systemd-resolved → DoT to Cloudflare
  # - wg-ns namespace: /etc/resolv.conf → 127.0.0.1 → dnsmasq → VPN DNS (10.128.0.1)
  # - Clean separation, no cross-namespace leaks
  services.nscd.enable = false;
  system.nssModules = lib.mkForce [ ];

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
      WG_DNS=$(${pkgs.gawk}/bin/awk '/^DNS/ {gsub(/DNS = /, ""); print}' /etc/wireguard/wg0.conf)

      # WG_MTU=$(${pkgs.gawk}/bin/awk '/^MTU/ {gsub(/MTU = /, ""); print}' /etc/wireguard/wg0.conf)
      # Hardcode MTU to 1420 since TAP interface should have MTU 1500 - 80 = 1420
      WG_MTU=1420

      WG_PUBLIC_KEY=$(${pkgs.gawk}/bin/awk '/^PublicKey/ {gsub(/PublicKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PRESHARED_KEY=$(${pkgs.gawk}/bin/awk '/^PresharedKey/ {gsub(/PresharedKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_ENDPOINT=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {gsub(/Endpoint = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PERSISTENT_KEEPALIVE=$(${pkgs.gawk}/bin/awk '/^PersistentKeepalive/ {gsub(/PersistentKeepalive = /, ""); print}' /etc/wireguard/wg0.conf)

      echo "Config extracted: Address=$WG_ADDRESS, DNS=$WG_DNS, Endpoint=$WG_ENDPOINT"

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
      # Create namespace-specific nsswitch.conf to bypass systemd-resolved
      cat > /etc/netns/wg-ns/nsswitch.conf <<-'EOF'
        hosts: files dns
        networks: files
        services: files
        protocols: files
      EOF
          
      # Create namespace-specific resolv.conf
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

  services.tailscale.enable = false;
  systemd.services.tailscaled-wg = {
    description = "Tailscale in WireGuard namespace";
    bindsTo = [ "netns@wg.service" ];
    after = [ "wg.service" "dnsmasq-wg.service" ];
    requires = [ "wg.service" "dnsmasq-wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
      PrivateMounts = true;

      # Override the DNS config
      BindReadOnlyPaths = [
        "/etc/netns/wg-ns/nsswitch.conf:/etc/nsswitch.conf"
        "/etc/netns/wg-ns/resolv.conf:/etc/resolv.conf"
        "/etc/netns/wg-ns/resolv.conf:/etc/static/resolv.conf"
        "/etc/netns/wg-ns/resolv.conf:/run/systemd/resolve/stub-resolv.conf"
      ];

      # Block unwanted sockets
      InaccessiblePaths = [ "/run/dbus/system_bus_socket" ];

      ExecStart =
        "${pkgs.tailscale}/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock";
      Restart = "always";
      RestartSec = "10s";
    };

    environment = {
      TS_NO_LOGS_NO_SUPPORT = "true";
      TS_DEBUG_MTU = "1340";
    };
  };

  systemd.services.tailscale-wg-configure = {
    description = "Ensure Tailscale DNS is disabled";
    after = [ "tailscaled-wg.service" ];
    requires = [ "tailscaled-wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      NetworkNamespacePath = "/var/run/netns/wg-ns";
    };

    script = ''
      # Enable IPv6 forwarding to stop Tailscale warning
      # (even though IPv6 is disabled, Tailscale checks this)
      ${pkgs.procps}/bin/sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null || true

      # Enable GRO forwarding on wg0 for performance
      ${pkgs.ethtool}/bin/ethtool -K wg0 rx-udp-gro-forwarding on rx-gro-list off 2>/dev/null || true

      # Wait for tailscaled to be ready
      for i in {1..30}; do
        ${pkgs.tailscale}/bin/tailscale status >/dev/null 2>&1 && break
        sleep 1
      done

      # Configure Tailscale with accept-dns=false
      ${pkgs.tailscale}/bin/tailscale up \
        --login-server=https://headscale.whimsical.cloud \
        --accept-dns=false \
        --accept-routes=true \
        --advertise-exit-node
    '';
  };

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
      # MSS clamping for nested WireGuard tunnels
      #
      # Current MTU configuration:
      #   - wg0: 1420 MTU (increased from 1320)
      #   - tailscale0: 1340 MTU
      #
      # With these MTU values, automatic PMTUD works correctly and MSS
      # clamping is technically not needed (tested without these rules
      # and performance was fine).
      #
      # However, we keep MSS clamping as defense-in-depth because:
      #   1. Zero performance cost
      #   2. Handles edge cases with variable TCP options
      #   3. Insurance if MTU settings change in future
      #   4. Previous config with wg0 MTU 1320 REQUIRED clamping
      #
      # If these rules cause issues, they can be safely removed.

      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A FORWARD \
        -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu

      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT \
        -p tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu

      ${pkgs.iproute2}/bin/ip netns exec wg-ns \
        ${pkgs.iptables}/bin/iptables -t mangle -A POSTROUTING \
        -p tcp --tcp-flags SYN,RST SYN \
        -o wg0 \
        -j TCPMSS --clamp-mss-to-pmtu

      echo "MSS clamping configured (defense-in-depth, not strictly required with current MTU)"
    '';
  };

  systemd.services.sockd = {
    description = "microsocks SOCKS5 proxy";
    after = [ "wg.service" "dnsmasq-wg.service" ];
    requires = [ "wg.service" "dnsmasq-wg.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
      PrivateMounts = true;

      # Override the DNS config
      BindReadOnlyPaths = [
        "/etc/netns/wg-ns/nsswitch.conf:/etc/nsswitch.conf"
        "/etc/netns/wg-ns/resolv.conf:/etc/resolv.conf"
        "/etc/netns/wg-ns/resolv.conf:/etc/static/resolv.conf"
        "/etc/netns/wg-ns/resolv.conf:/run/systemd/resolve/stub-resolv.conf"
      ];

      # Block unwanted sockets
      InaccessiblePaths = [ "/run/dbus/system_bus_socket" ];

      ExecStart = "${pkgs.microsocks}/bin/microsocks -i 0.0.0.0 -p 1080";
      Restart = "always";
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
    serviceConfig = {
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:1080";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
    };
  };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH
      1080 # SOCKS proxy
    ];
  };

  # Helpful aliases
  environment.shellAliases = {
    wg-status = "sudo ip netns exec wg-ns wg show";
    vpn-ip = "sudo ip netns exec wg-ns curl -s ifconfig.me";
    real-ip = "curl -s ifconfig.me";
  };
}
