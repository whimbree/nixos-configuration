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
    hypervisor = "qemu";
    mem = 6144; # 4096
    # hotplugMem = 4096;
    hotplugMem = 0;
    vcpu = 4;
    vsock.cid = vmConfig.tier * 100 + vmConfig.index;

    # Share VPN config from host
    shares = [
      {
        source = "/microvms/airvpn-sweden/var/lib/tailscale";
        mountPoint = "/var/lib/tailscale";
        tag = "tailscale";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/etc/wireguard";
        mountPoint = "/etc/wireguard";
        tag = "wireguard";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/var/lib/deluge";
        mountPoint = "/var/lib/deluge";
        tag = "deluge";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/var/lib/prowlarr";
        mountPoint = "/var/lib/prowlarr";
        tag = "prowlarr";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/var/lib/sonarr";
        mountPoint = "/var/lib/sonarr";
        tag = "sonarr";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/var/lib/radarr";
        mountPoint = "/var/lib/radarr";
        tag = "radarr";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/var/lib/lidarr";
        mountPoint = "/var/lib/lidarr";
        tag = "lidarr";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/microvms/airvpn-sweden/var/lib/jellyseerr";
        mountPoint = "/var/lib/private/jellyseerr";
        tag = "jellyseerr";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
    ];
  };

  fileSystems."/shows" = {
    device = "10.0.0.0:/export/media/shows";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/movies" = {
    device = "10.0.0.0:/export/media/movies";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/music" = {
    device = "10.0.0.0:/export/media/music";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
    ];
  };

  fileSystems."/downloads" = {
    device = "10.0.0.0:/export/downloads";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.2"
      "rsize=131072"
      "wsize=131072"
      "soft"
      "noatime"
      "nodiratime"
      "_netdev"
      "x-systemd.automount"
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
  systemd.services.deluged.after = [ "netns@wg.service" "wg.service" ];
  systemd.services.deluged.serviceConfig.NetworkNamespacePath =
    "/var/run/netns/wg-ns";
  systemd.services.deluged.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.deluged.serviceConfig.RestartSec = lib.mkForce 5;
  # # binding delugeweb to network namespace
  systemd.services.delugeweb.bindsTo = [ "netns@wg.service" ];
  systemd.services.delugeweb.requires =
    [ "network-online.target" "wg.service" ];
  systemd.services.delugeweb.after = [ "netns@wg.service" "wg.service" ];
  systemd.services.delugeweb.serviceConfig.NetworkNamespacePath =
    "/var/run/netns/wg-ns";
  systemd.services.delugeweb.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.delugeweb.serviceConfig.RestartSec = lib.mkForce 5;
  # a socket is necessary to allow delugeweb to be accesed from outside the namespace
  systemd.sockets."proxy-to-delugeweb" = {
    enable = true;
    description = "Socket for Proxy to Deluge Web";
    listenStreams = [ "8112" ];
    wantedBy = [ "sockets.target" ];
  };
  # creating proxy service on socket, which forwards the same port from the root namespace to the isolated namespace
  systemd.services."proxy-to-delugeweb" = {
    enable = true;
    description = "Proxy to Deluge Web in Network Namespace";
    requires = [ "delugeweb.service" "proxy-to-delugeweb.socket" ];
    after = [ "delugeweb.service" "proxy-to-delugeweb.socket" ];
    serviceConfig = {
      ExecStart =
        "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8112";
      NetworkNamespacePath = "/var/run/netns/wg-ns";
    };
  };

  services.prowlarr = {
    enable = true;
    # settings.server.port = 9696;
  };
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    StateDirectory = lib.mkForce "";
    User = "fileshare";
    Group = "fileshare";
  };
  # binding prowlarr to network namespace
  # systemd.services.prowlarr.bindsTo = [ "netns@wg.service" ];
  # systemd.services.prowlarr.requires = [ "network-online.target" "wg.service" ];
  # systemd.services.prowlarr.after = [ "netns@wg.service" "wg.service" ];
  # systemd.services.prowlarr.serviceConfig.NetworkNamespacePath =
  #   "/var/run/netns/wg-ns";
  systemd.services.prowlarr.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.prowlarr.serviceConfig.RestartSec = lib.mkForce 5;
  # # Create socket for exposing Prowlarr UI
  # systemd.sockets."proxy-to-prowlarr" = {
  #   enable = true;
  #   description = "Socket for Proxy to Prowlarr";
  #   listenStreams = [ "9696" ];
  #   wantedBy = [ "sockets.target" ];
  # };
  # # Proxy service
  # systemd.services."proxy-to-prowlarr" = {
  #   enable = true;
  #   description = "Proxy to prowlarr in Network Namespace";
  #   requires = [ "prowlarr.service" "proxy-to-prowlarr.socket" ];
  #   after = [ "prowlarr.service" "proxy-to-prowlarr.socket" ];
  #   serviceConfig = {
  #     ExecStart =
  #       "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:9696";
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";
  #   };
  # };

  services.flaresolverr = {
    enable = true;
    port = 8191;
  };
  # binding flaresolverr to network namespace
  # systemd.services.flaresolverr.bindsTo = [ "netns@wg.service" ];
  # systemd.services.flaresolverr.requires =
  #   [ "network-online.target" "wg.service" ];
  # systemd.services.flaresolverr.after = [ "netns@wg.service" "wg.service" ];
  # systemd.services.flaresolverr.serviceConfig.NetworkNamespacePath =
  #   "/var/run/netns/wg-ns";
  systemd.services.flaresolverr.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.flaresolverr.serviceConfig.RestartSec = lib.mkForce 5;
  # # Create socket for exposing flaresolverr
  # systemd.sockets."proxy-to-flaresolverr" = {
  #   enable = true;
  #   description = "Socket for Proxy to flaresolverr";
  #   listenStreams = [ "8191" ];
  #   wantedBy = [ "sockets.target" ];
  # };
  # # Proxy service
  # systemd.services."proxy-to-flaresolverr" = {
  #   enable = true;
  #   description = "Proxy to flaresolverr in Network Namespace";
  #   requires = [ "flaresolverr.service" "proxy-to-flaresolverr.socket" ];
  #   after = [ "flaresolverr.service" "proxy-to-flaresolverr.socket" ];
  #   serviceConfig = {
  #     ExecStart =
  #       "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8191";
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";
  #   };
  # };

  services.sonarr = {
    enable = true;
    user = "fileshare";
    group = "fileshare";
    dataDir = "/var/lib/sonarr";
  };
  systemd.services.sonarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    StateDirectory = lib.mkForce "";
    User = "fileshare";
    Group = "fileshare";
  };
  # binding sonarr to network namespace
  # systemd.services.sonarr.bindsTo = [ "netns@wg.service" ];
  # systemd.services.sonarr.requires = [ "network-online.target" "wg.service" ];
  # systemd.services.sonarr.after = [ "netns@wg.service" "wg.service" ];
  # systemd.services.sonarr.serviceConfig.NetworkNamespacePath =
  #   "/var/run/netns/wg-ns";
  systemd.services.sonarr.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.sonarr.serviceConfig.RestartSec = lib.mkForce 5;
  # Create socket for exposing sonarr UI
  # systemd.sockets."proxy-to-sonarr" = {
  #   enable = true;
  #   description = "Socket for Proxy to Sonarr";
  #   listenStreams = [ "8989" ];
  #   wantedBy = [ "sockets.target" ];
  # };
  # # Proxy service
  # systemd.services."proxy-to-sonarr" = {
  #   enable = true;
  #   description = "Proxy to Sonarr in Network Namespace";
  #   requires = [ "sonarr.service" "proxy-to-sonarr.socket" ];
  #   after = [ "sonarr.service" "proxy-to-sonarr.socket" ];
  #   serviceConfig = {
  #     ExecStart =
  #       "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8989";
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";
  #   };
  # };

  services.radarr = {
    enable = true;
    user = "fileshare";
    group = "fileshare";
    dataDir = "/var/lib/radarr";
  };
  systemd.services.radarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    StateDirectory = lib.mkForce "";
    User = "fileshare";
    Group = "fileshare";
  };
  # # binding radarr to network namespace
  # systemd.services.radarr.bindsTo = [ "netns@wg.service" ];
  # systemd.services.radarr.requires = [ "network-online.target" "wg.service" ];
  # systemd.services.radarr.after = [ "netns@wg.service" "wg.service" ];
  # systemd.services.radarr.serviceConfig.NetworkNamespacePath =
  #   "/var/run/netns/wg-ns";
  systemd.services.radarr.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.radarr.serviceConfig.RestartSec = lib.mkForce 5;
  # # Create socket for exposing radarr UI
  # systemd.sockets."proxy-to-radarr" = {
  #   enable = true;
  #   description = "Socket for Proxy to radarr";
  #   listenStreams = [ "7878" ];
  #   wantedBy = [ "sockets.target" ];
  # };
  # # Proxy service
  # systemd.services."proxy-to-radarr" = {
  #   enable = true;
  #   description = "Proxy to radarr in Network Namespace";
  #   requires = [ "radarr.service" "proxy-to-radarr.socket" ];
  #   after = [ "radarr.service" "proxy-to-radarr.socket" ];
  #   serviceConfig = {
  #     ExecStart =
  #       "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:7878";
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";
  #   };
  # };

  services.lidarr = {
    enable = true;
    user = "fileshare";
    group = "fileshare";
    dataDir = "/var/lib/lidarr";
  };
  systemd.services.lidarr.serviceConfig = {
    DynamicUser = lib.mkForce false;
    StateDirectory = lib.mkForce "";
    User = "fileshare";
    Group = "fileshare";
  };
  # binding lidarr to network namespace
  # systemd.services.lidarr.bindsTo = [ "netns@wg.service" ];
  # systemd.services.lidarr.requires = [ "network-online.target" "wg.service" ];
  # systemd.services.lidarr.after = [ "netns@wg.service" "wg.service" ];
  # systemd.services.lidarr.serviceConfig.NetworkNamespacePath =
  #   "/var/run/netns/wg-ns";
  systemd.services.lidarr.serviceConfig.Restart = lib.mkForce "always";
  systemd.services.lidarr.serviceConfig.RestartSec = lib.mkForce 5;
  # # Create socket for exposing lidarr UI
  # systemd.sockets."proxy-to-lidarr" = {
  #   enable = true;
  #   description = "Socket for Proxy to lidarr";
  #   listenStreams = [ "8686" ];
  #   wantedBy = [ "sockets.target" ];
  # };
  # # Proxy service
  # systemd.services."proxy-to-lidarr" = {
  #   enable = true;
  #   description = "Proxy to lidarr in Network Namespace";
  #   requires = [ "lidarr.service" "proxy-to-lidarr.socket" ];
  #   after = [ "lidarr.service" "proxy-to-lidarr.socket" ];
  #   serviceConfig = {
  #     ExecStart =
  #       "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8686";
  #     NetworkNamespacePath = "/var/run/netns/wg-ns";
  #   };
  # };

  # services.jellyseerr = {
  #   enable = true;
  #   configDir = "/var/lib/private/jellyseerr/config";
  # };

  # Firewall configuration
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH
      1080 # SOCKS proxy
      8112 # Deluge
      9696 # Prowlarr
      8191 # Flaresolverr
      8989 # Sonarr
      7878 # Radarr
      8686 # Lidarr
      5055 # Jellyseerr
    ];
  };

  # Helpful aliases
  environment.shellAliases = {
    wg-status = "sudo ip netns exec wg-ns wg show";
    vpn-ip = "sudo ip netns exec wg-ns curl -s ifconfig.me";
    real-ip = "curl -s ifconfig.me";
  };
}
