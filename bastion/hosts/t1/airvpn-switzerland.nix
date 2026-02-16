{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Set to true to enable auto-updates
  enableAutoUpdate = true;
in {
  microvm = {
    # vsock.cid = vmConfig.tier * 100 + vmConfig.index;
    mem = 4096;
    hotplugMem = 4096;
    vcpu = 4;

    # Share VPN config from host
    shares = [
      {
        source = "/microvms/airvpn-switzerland/var/lib/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tailscale";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-switzerland/etc/wireguard";
        mountPoint = "/etc/wireguard";
        tag = "wireguard";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-switzerland/var/slskd";
        mountPoint = "/var/slskd";
        tag = "var-slskd";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/downloads/metube";
        mountPoint = "/metube";
        tag = "downloads-metube";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/ocean/downloads/slskd";
        mountPoint = "/downloads/slskd";
        tag = "downloads-slskd";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/blockchain/monerod";
        mountPoint = "/var/lib/monero";
        tag = "blockchain-monero";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];

    volumes = [{
      image = "containers-cache.img";
      mountPoint = "/var/lib/containers";
      size = 1024 * 20; # 20GB cache
      fsType = "ext4";
      autoCreate = true;
    }];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Auto-update timer (only active if enableAutoUpdate = true)
  systemd.timers.podman-auto-update = lib.mkIf enableAutoUpdate {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:00"; # 3 AM
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update = lib.mkIf enableAutoUpdate {
    description = "Auto-update containers";
    serviceConfig = { Type = "oneshot"; };
    script = ''
      ${pkgs.podman}/bin/podman auto-update
    '';
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

  # # Disable nscd (Name Service Cache Daemon) to prevent DNS leaks in the VPN namespace.
  # #
  # # THE PROBLEM:
  # # nscd caches DNS lookups at the system level via /var/run/nscd/socket. This socket
  # # exists in the MOUNT namespace (not network namespace), so processes in wg-ns can
  # # access it. When apps in wg-ns query DNS:
  # #   1. glibc checks if /var/run/nscd/socket exists
  # #   2. Connects to nscd (running in ROOT namespace)
  # #   3. nscd reads ROOT's /etc/nsswitch.conf
  # #   4. nscd queries systemd-resolved in ROOT namespace
  # #   5. DNS leaks to Cloudflare, completely bypassing our VPN DNS setup
  # #
  # # THE SOLUTION:
  # # Disabling nscd prevents cross-namespace DNS contamination. However, NixOS requires
  # # us to also disable NSS modules when nscd is disabled. This is fine - without NSS
  # # modules, glibc falls back to classic behavior: directly reading /etc/resolv.conf.
  # #
  # # RESULT:
  # # - Root namespace: /etc/resolv.conf → 127.0.0.53 → systemd-resolved → DoT to Cloudflare
  # # - wg-ns namespace: /etc/resolv.conf → 127.0.0.1 → dnsmasq → VPN DNS
  # # - Clean separation, no cross-namespace leaks
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
      WG_MTU=$(${pkgs.gawk}/bin/awk '/^MTU/ {gsub(/MTU = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_DNS=$(${pkgs.gawk}/bin/awk '/^DNS/ {gsub(/DNS = /, ""); print}' /etc/wireguard/wg0.conf)

      WG_PUBLIC_KEY=$(${pkgs.gawk}/bin/awk '/^PublicKey/ {gsub(/PublicKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PRESHARED_KEY=$(${pkgs.gawk}/bin/awk '/^PresharedKey/ {gsub(/PresharedKey = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_ENDPOINT=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {gsub(/Endpoint = /, ""); print}' /etc/wireguard/wg0.conf)
      WG_PERSISTENT_KEEPALIVE=$(${pkgs.gawk}/bin/awk '/^PersistentKeepalive/ {gsub(/PersistentKeepalive = /, ""); print}' /etc/wireguard/wg0.conf)

      echo "Config extracted: Address=$WG_ADDRESS, MTU=$WG_MTU, Endpoint=$WG_ENDPOINT"

      # Create WireGuard interface in main namespace (where it can reach internet)
      ${pkgs.iproute2}/bin/ip link add wg0 type wireguard

      # Set MTU before configuring crypto (important for some networks)
      ${pkgs.iproute2}/bin/ip link set wg0 mtu $WG_MTU

      # Configure WireGuard crypto and peer settings in main namespace
      # This allows the handshake to happen while interface can reach VPN server
      ${pkgs.wireguard-tools}/bin/wg set wg0 \
        private-key <(echo "$WG_PRIVATE_KEY") \
        peer "$WG_PUBLIC_KEY" \
        preshared-key <(echo "$WG_PRESHARED_KEY") \
        allowed-ips 0.0.0.0/0 \
        endpoint "$WG_ENDPOINT" \
        persistent-keepalive "$WG_PERSISTENT_KEEPALIVE"

      # Move to namespace BEFORE adding IP/routes
      ${pkgs.iproute2}/bin/ip link set wg0 netns wg-ns up

      # Route for IP address inside the isolated namespace
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip addr add $WG_ADDRESS dev wg0
      # Route for all traffic to go through wg0
      ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.iproute2}/bin/ip route add default dev wg0

      echo "WireGuard interface moved to vpn namespace and configured"

      echo "Waiting for WireGuard handshake..."
      ATTEMPTS=0
      MAX_ATTEMPTS=30  # 5 minutes with 10-second intervals

      while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.wireguard-tools}/bin/wg show | grep -q "latest handshake"; then
          VPN_IP=$(${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.curl}/bin/curl -s --max-time 10 ifconfig.me || echo "Failed")
          echo "WireGuard handshake successful after $((ATTEMPTS * 10)) seconds, VPN IP: $VPN_IP"
          break
        else
          ATTEMPTS=$((ATTEMPTS + 1))
          echo "Attempt $ATTEMPTS/$MAX_ATTEMPTS: No handshake yet, retrying in 2 seconds..."
          if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
            echo "WireGuard handshake failed after $((MAX_ATTEMPTS * 2)) seconds"
            echo "Current WireGuard status:"
            ${pkgs.iproute2}/bin/ip netns exec wg-ns ${pkgs.wireguard-tools}/bin/wg show
            echo "Check configuration, endpoint reachability, and firewall settings"
            exit 1
          fi
          sleep 2
        fi
      done
    '';

    preStop = ''
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
        # "/etc/netns/wg-ns/nsswitch.conf:/etc/nsswitch.conf"
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

    environment = { TS_NO_LOGS_NO_SUPPORT = "true"; };
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
        # "/etc/netns/wg-ns/nsswitch.conf:/etc/nsswitch.conf"
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

  # create fileshare user for services
  users.users.fileshare = {
    createHome = false;
    isSystemUser = true;
    group = "fileshare";
    uid = 1420;
  };
  users.groups.fileshare.gid = 1420;

  systemd.services.podman-metube = {
    requires = [ "wg.service" ];
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
    };
  };
  virtualisation.oci-containers.containers."metube" = {
    autoStart = true;
    image = "ghcr.io/alexta69/metube:latest";
    volumes = [ "/metube:/metube" ];
    environment = {
      UID = "1420";
      GID = "1420";
      DOWNLOAD_DIR = "/metube";
    };
    ports = [ "0.0.0.0:8081:8081" ]; # metube on port 8081
    extraOptions = [
      # networks
      "--network=ns:/var/run/netns/wg-ns"
    ];
  };
  # Create socket for exposing metube
  systemd.sockets."proxy-to-metube" = {
    enable = true;
    description = "Socket for Proxy to metube";
    listenStreams = [ "8081" ];
    wantedBy = [ "sockets.target" ];
  };
  # Proxy service
  systemd.services."proxy-to-metube" = {
    enable = true;
    description = "Proxy to metube in Network Namespace";
    requires = [ "podman-metube.service" "proxy-to-metube.socket" ];
    after = [ "podman-metube.service" "proxy-to-metube.socket" ];
    serviceConfig = {
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8081";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
    };
  };

  systemd.services.monero.bindsTo = [ "netns@wg.service" ];
  systemd.services.monero.requires = [ "network-online.target" "wg.service" ];
  systemd.services.monero.after = [ "netns@wg.service" "wg.service" ];
  systemd.services.monero.serviceConfig.NetworkNamespacePath =
    "/var/run/netns/wg-ns";
  systemd.services.monero.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.monero.serviceConfig.RestartSec = lib.mkForce 5;
  services.monero = {
    enable = true;
    dataDir = "/var/lib/monero";
    # Run as public node
    extraConfig = ''
      p2p-bind-ip=0.0.0.0
      p2p-bind-port=46280

      rpc-restricted-bind-ip=0.0.0.0
      rpc-restricted-bind-port=46279

      # Disable UPnP port mapping
      no-igd=1

      # Public-node
      public-node=1

      # ZMQ configuration
      no-zmq=1

      # Block known-malicious nodes from a DNSBL
      enable-dns-blocklist=1
    '';
  };
  # Create socket for exposing monerod rpc
  systemd.sockets."proxy-to-monero" = {
    enable = true;
    description = "Socket for Proxy to monero";
    listenStreams = [ "46279" ];
    wantedBy = [ "sockets.target" ];
  };
  # Proxy service
  systemd.services."proxy-to-monero" = {
    enable = true;
    description = "Proxy to monero in Network Namespace";
    requires = [ "monero.service" "proxy-to-monero.socket" ];
    after = [ "monero.service" "proxy-to-monero.socket" ];
    serviceConfig = {
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:46279";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
    };
  };

  # services.redlib = {
  #   enable = true;
  #   port = 7676;
  # };
  # systemd.services.redlib.serviceConfig = {
  #   DynamicUser = lib.mkForce false;
  #   StateDirectory = lib.mkForce "";
  #   User = "fileshare";
  #   Group = "fileshare";
  # };
  # systemd.services.redlib.serviceConfig.Restart = lib.mkForce "always";
  # systemd.services.redlib.serviceConfig.RestartSec = lib.mkForce 5;

  # MUST BE SECURED WITH ANUBIS
  systemd.services.podman-redlib = {
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
    };
  };
  virtualisation.oci-containers.containers."redlib" = {
    autoStart = true;
    image = "quay.io/redlib/redlib:latest";
    ports = [ "0.0.0.0:7676:8080" ]; # metube on port 7676
    extraOptions = [
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 http://0.0.0.0:8080/settings || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
    ];
  };

  systemd.services.podman-slskd = {
    requires = [ "wg.service" ];
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
    };
  };
  virtualisation.oci-containers.containers."slskd" = {
    autoStart = true;
    image = "ghcr.io/slskd/slskd:latest";
    volumes = [ "/var/slskd:/app"
      "/var/slskd:/app"
      "/downloads/slskd:/downloads/slskd"
     ];
    environment = {
      SLSKD_REMOTE_CONFIGURATION = "false";
      SLSKD_DOWNLOADS_DIR = "/downloads/slskd/complete";
      SLSKD_INCOMPLETE_DIR = "/downloads/slskd/incomplete";
    };
    environmentFiles = [ "/var/slskd/.env" ];
    ports = [ "0.0.0.0:5030:5030" ]; # slskd on port 5030
    extraOptions = [
      # networks
      "--network=ns:/var/run/netns/wg-ns"
    ];
  };
  # Create socket for exposing slskd
  systemd.sockets."proxy-to-slskd" = {
    enable = true;
    description = "Socket for Proxy to slskd";
    listenStreams = [ "5030" ];
    wantedBy = [ "sockets.target" ];
  };
  # Proxy service
  systemd.services."proxy-to-slskd" = {
    enable = true;
    description = "Proxy to slskd in Network Namespace";
    requires = [ "podman-slskd.service" "proxy-to-slskd.socket" ];
    after = [ "podman-slskd.service" "proxy-to-slskd.socket" ];
    serviceConfig = {
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:5030";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
    };
  };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH
      1080 # SOCKS proxy
      8081 # metube
      7676 # redlib
      46279 # monero
      5030 # slskd
    ];
  };

  # Helpful aliases
  environment.shellAliases = {
    wg-status = "sudo ip netns exec wg-ns wg show";
    vpn-ip = "sudo ip netns exec wg-ns curl -s ifconfig.me";
    real-ip = "curl -s ifconfig.me";
  };
}
