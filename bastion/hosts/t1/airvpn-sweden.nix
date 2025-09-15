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
    vsock.cid = vmConfig.tier * 100 + vmConfig.index;
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

  systemd.services."netns@" = {
    description = "%I network namespace";
    # Delay network.target until this unit has finished starting up.
    before = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      PrivateNetwork = true;
      ExecStart = "${pkgs.writers.writeDash "netns-up" ''
        ${pkgs.iproute2}/bin/ip netns add $1
        ${pkgs.utillinux}/bin/umount /var/run/netns/$1
        ${pkgs.utillinux}/bin/mount --bind /proc/self/ns/net /var/run/netns/$1
      ''} %I";
      ExecStop = "${pkgs.iproute2}/bin/ip netns del %I";
      # This is required since systemd commit c2da3bf, shipped in systemd 254.
      # See discussion at https://github.com/systemd/systemd/issues/28686
      PrivateMounts = false;
    };
  };

  # systemd.services.wg = {
  #   description = "wg network interface in isolated namespace";
  #   # Absolutely require the wg network namespace to exist.
  #   bindsTo = [ "netns@wg.service" ];
  #   # Require a network connection.
  #   requires = [ "network-online.target" "nss-lookup.target" ];
  #   # Start after and stop before those units.
  #   after = [ "netns@wg.service" "network-online.target" "nss-lookup.target" ];
  #   # wantedBy = [ "multi-user.target" ];
    
  #   serviceConfig = {
  #     Type = "oneshot";
  #     RemainAfterExit = true;
  #     User = "root";
  #   };
    
  #   script = ''
  #     echo "Setting up WireGuard interface..."
      
  #     # Extract configuration from wg0.conf file
  #     WG_ADDRESS=$(${pkgs.gawk}/bin/awk '/^Address/ {gsub(/Address = /, ""); print}' /etc/wireguard/wg0.conf)
  #     WG_PRIVATE_KEY=$(${pkgs.gawk}/bin/awk '/^PrivateKey/ {gsub(/PrivateKey = /, ""); print}' /etc/wireguard/wg0.conf)
  #     WG_MTU=$(${pkgs.gawk}/bin/awk '/^MTU/ {gsub(/MTU = /, ""); print}' /etc/wireguard/wg0.conf)
  #     WG_DNS=$(${pkgs.gawk}/bin/awk '/^DNS/ {gsub(/DNS = /, ""); print}' /etc/wireguard/wg0.conf)
      
  #     WG_PUBLIC_KEY=$(${pkgs.gawk}/bin/awk '/^PublicKey/ {gsub(/PublicKey = /, ""); print}' /etc/wireguard/wg0.conf)
  #     WG_PRESHARED_KEY=$(${pkgs.gawk}/bin/awk '/^PresharedKey/ {gsub(/PresharedKey = /, ""); print}' /etc/wireguard/wg0.conf)
  #     WG_ENDPOINT=$(${pkgs.gawk}/bin/awk '/^Endpoint/ {gsub(/Endpoint = /, ""); print}' /etc/wireguard/wg0.conf)
  #     WG_PERSISTENT_KEEPALIVE=$(${pkgs.gawk}/bin/awk '/^PersistentKeepalive/ {gsub(/PersistentKeepalive = /, ""); print}' /etc/wireguard/wg0.conf)
      
  #     echo "Config extracted: Address=$WG_ADDRESS, MTU=$WG_MTU, Endpoint=$WG_ENDPOINT"
      
  #     # Step 1: Create WireGuard interface in main namespace (where it can reach internet)
  #     ${pkgs.iproute2}/bin/ip link add wg0 type wireguard
      
  #     # Step 2: Set MTU before configuring crypto (important for some networks)
  #     ${pkgs.iproute2}/bin/ip link set wg0 mtu $WG_MTU
      
  #     # Step 3: Configure WireGuard crypto and peer settings in main namespace
  #     # This allows the handshake to happen while interface can reach VPN server
  #     ${pkgs.wireguard-tools}/bin/wg set wg0 \
  #       private-key <(echo "$WG_PRIVATE_KEY") \
  #       peer "$WG_PUBLIC_KEY" \
  #       allowed-ips 0.0.0.0/0 \
  #       endpoint "$WG_ENDPOINT" \
  #       persistent-keepalive "$WG_PERSISTENT_KEEPALIVE"
      
  #     # Step 4: Bring interface up in main namespace to establish handshake
  #     ${pkgs.iproute2}/bin/ip link set wg0 up
      
  #     echo "Waiting for WireGuard handshake in main namespace..."
  #     # Wait a moment for handshake to establish while interface can reach internet
  #     ${pkgs.coreutils}/bin/sleep 5
      
  #     # Step 5: THE KEY STEP - Move the connected interface to isolated vpn namespace
  #     # After this point, wg0 can only communicate through the VPN tunnel
  #     ${pkgs.iproute2}/bin/ip link set wg0 netns vpn
      
  #     # Step 6: Configure IP address inside the isolated namespace
  #     ${pkgs.iproute2}/bin/ip -n vpn address add "$WG_ADDRESS" dev wg0
      
  #     # Step 7: Set up routing inside the namespace - all traffic goes through VPN
  #     ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg0
      
  #     # Step 8: Configure DNS inside the namespace
  #     if [ -n "$WG_DNS" ]; then
  #       # Create resolv.conf for the namespace
  #       echo "nameserver $WG_DNS" > /tmp/resolv.conf.vpn
  #       ${pkgs.iproute2}/bin/ip netns exec vpn cp /tmp/resolv.conf.vpn /etc/resolv.conf
  #     fi
      
  #     echo "✅ WireGuard interface moved to vpn namespace and configured"
      
  #     # Step 9: Verify the connection worked
  #     if ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.wireguard-tools}/bin/wg show | grep -q "latest handshake"; then
  #       VPN_IP=$(${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.curl}/bin/curl -s --max-time 10 ifconfig.me || echo "Failed")
  #       echo "✅ WireGuard handshake successful, VPN IP: $VPN_IP"
  #     else
  #       echo "⚠️  WireGuard interface moved but no handshake yet"
  #       ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.wireguard-tools}/bin/wg show
  #     fi
  #   '';
    
  #   preStop = ''
  #     echo "Cleaning up WireGuard interface..."
  #     # Remove interface from vpn namespace (this also brings it down)
  #     ${pkgs.iproute2}/bin/ip -n wg link del wg0 || true
  #   '';
  # };


  # Test adding interface manually with script (AFTER networking is stable)
  systemd.services.test-add-interface = {
    description = "Test adding interface manually";
    after = [ "network-debug.service" ];
    # Don't auto-start this - run manually with: systemctl start test-add-interface
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    
    script = ''
      LOG="/etc/wireguard/network-debug.log"

      echo "" > $LOG
      
      echo "=====================================================" >> $LOG
      echo "=== NETWORKD INTERFACE DEBUG - $(date) ===" >> $LOG
      echo "=====================================================" >> $LOG
      
      echo "" >> $LOG
      echo "=== INITIAL SYSTEM STATE ===" >> $LOG
      
      echo "--- systemd-networkd status ---" >> $LOG
      ${pkgs.systemd}/bin/systemctl show systemd-networkd --property=SubState,ActiveState,MainPID,ActiveEnterTimestamp >> $LOG
      ${pkgs.systemd}/bin/systemctl status systemd-networkd --no-pager >> $LOG 2>&1
      
      echo "" >> $LOG
      echo "--- Interface list ---" >> $LOG
      ${pkgs.systemd}/bin/networkctl list >> $LOG 2>&1
      
      echo "" >> $LOG
      echo "--- Interface details ---" >> $LOG
      ${pkgs.iproute2}/bin/ip addr show >> $LOG
      
      echo "" >> $LOG
      echo "--- Current routing table ---" >> $LOG
      ${pkgs.iproute2}/bin/ip route show table all >> $LOG
      
      echo "" >> $LOG
      echo "--- Current routing rules ---" >> $LOG
      ${pkgs.iproute2}/bin/ip rule show >> $LOG
      
      echo "" >> $LOG
      echo "--- Default route details ---" >> $LOG
      ${pkgs.iproute2}/bin/ip route show default >> $LOG
      echo "Default route command output: $(${pkgs.iproute2}/bin/ip route show default)" >> $LOG
      
      echo "" >> $LOG
      echo "--- Route to gateway ---" >> $LOG
      ${pkgs.iproute2}/bin/ip route get 10.0.0.0 >> $LOG 2>&1
      
      echo "" >> $LOG
      echo "--- systemd-networkd recent logs ---" >> $LOG
      ${pkgs.systemd}/bin/journalctl -u systemd-networkd --since "2 minutes ago" --no-pager >> $LOG 2>&1
      
      echo "" >> $LOG
      echo "--- Initial connectivity test ---" >> $LOG
      if ${pkgs.iputils}/bin/ping -c 1 -W 2 10.0.0.0 >> $LOG 2>&1; then
        echo "✓ Initial connectivity: WORKING" >> $LOG
      else
        echo "✗ Initial connectivity: BROKEN" >> $LOG
      fi
      
      echo "" >> $LOG
      echo "=== CREATING TEST INTERFACE ===" >> $LOG
      echo "Creating veth pair: veth0 <-> veth1" >> $LOG
      
      # Create the interface
      ${pkgs.iproute2}/bin/ip link add veth0 type veth peer name veth1 >> $LOG 2>&1
      
      echo "Interface created. Checking immediate state..." >> $LOG
      
      echo "" >> $LOG
      echo "--- Interface list after creation ---" >> $LOG
      ${pkgs.systemd}/bin/networkctl list >> $LOG 2>&1
      
      echo "" >> $LOG
      echo "--- All interfaces after creation ---" >> $LOG
      ${pkgs.iproute2}/bin/ip addr show >> $LOG
      
      echo "" >> $LOG
      echo "--- Routing table after creation ---" >> $LOG
      ${pkgs.iproute2}/bin/ip route show table all >> $LOG
      
      echo "" >> $LOG
      echo "--- Default route after creation ---" >> $LOG
      ${pkgs.iproute2}/bin/ip route show default >> $LOG
      echo "Default route command output: $(${pkgs.iproute2}/bin/ip route show default)" >> $LOG
      
      echo "" >> $LOG
      echo "--- Route to gateway after creation ---" >> $LOG
      ${pkgs.iproute2}/bin/ip route get 10.0.0.0 >> $LOG 2>&1 || echo "Route lookup failed" >> $LOG
      
      echo "" >> $LOG
      echo "--- systemd-networkd logs since interface creation ---" >> $LOG
      ${pkgs.systemd}/bin/journalctl -u systemd-networkd --since "30 seconds ago" --no-pager >> $LOG 2>&1
      
      echo "" >> $LOG
      echo "--- Immediate connectivity test ---" >> $LOG
      if ${pkgs.iputils}/bin/ping -c 1 -W 2 10.0.0.0 >> $LOG 2>&1; then
        echo "✓ Immediate connectivity: WORKING" >> $LOG
        IMMEDIATE_STATE="WORKING"
      else
        echo "✗ Immediate connectivity: BROKEN" >> $LOG
        IMMEDIATE_STATE="BROKEN"
      fi
      
      echo "" >> $LOG
      echo "--- Waiting 3 seconds and testing again ---" >> $LOG
      sleep 3
      
      echo "After 3 second delay:" >> $LOG
      ${pkgs.iproute2}/bin/ip route show default >> $LOG
      echo "Default route after delay: $(${pkgs.iproute2}/bin/ip route show default)" >> $LOG
      
      if ${pkgs.iputils}/bin/ping -c 1 -W 2 10.0.0.0 >> $LOG 2>&1; then
        echo "✓ Delayed connectivity: WORKING" >> $LOG
        DELAYED_STATE="WORKING"
      else
        echo "✗ Delayed connectivity: BROKEN" >> $LOG
        DELAYED_STATE="BROKEN"
      fi
      
      echo "" >> $LOG
      echo "--- Additional diagnostic tests ---" >> $LOG
      
      echo "Testing ping with explicit source IP:" >> $LOG
      ${pkgs.iputils}/bin/ping -c 1 -W 2 -S 10.0.1.2 10.0.0.0 >> $LOG 2>&1 || echo "Explicit source ping failed" >> $LOG
      
      echo "" >> $LOG
      echo "Testing ping with explicit interface:" >> $LOG
      ${pkgs.iputils}/bin/ping -c 1 -W 2 -I ens4 10.0.0.0 >> $LOG 2>&1 || echo "Explicit interface ping failed" >> $LOG
      
      echo "" >> $LOG
      echo "Checking ARP table:" >> $LOG
      ${pkgs.iproute2}/bin/ip neighbor show >> $LOG
      
      echo "" >> $LOG
      echo "=== TESTING ROUTE RESTORATION ===" >> $LOG
      
      if [ "$DELAYED_STATE" = "BROKEN" ]; then
        echo "Attempting to restore default route..." >> $LOG
        
        # Try deleting and re-adding the route
        ${pkgs.iproute2}/bin/ip route del default >> $LOG 2>&1 || echo "No default route to delete" >> $LOG
        ${pkgs.iproute2}/bin/ip route add default via 10.0.0.0 dev ens4 src 10.0.1.2 metric 10 >> $LOG 2>&1
        
        echo "After route restoration:" >> $LOG
        ${pkgs.iproute2}/bin/ip route show default >> $LOG
        
        if ${pkgs.iputils}/bin/ping -c 1 -W 2 10.0.0.0 >> $LOG 2>&1; then
          echo "✓ Connectivity restored!" >> $LOG
          RESTORED_STATE="WORKING"
        else
          echo "✗ Still broken after route restoration" >> $LOG
          RESTORED_STATE="BROKEN"
        fi
      fi
      
      echo "" >> $LOG
      echo "=== CLEANING UP ===" >> $LOG
      ${pkgs.iproute2}/bin/ip link delete veth0 >> $LOG 2>&1 || echo "Failed to delete veth0" >> $LOG
      
      echo "After cleanup:" >> $LOG
      ${pkgs.iproute2}/bin/ip route show default >> $LOG
      
      if ${pkgs.iputils}/bin/ping -c 1 -W 2 10.0.0.0 >> $LOG 2>&1; then
        echo "✓ Connectivity after cleanup: WORKING" >> $LOG
        CLEANUP_STATE="WORKING"
      else
        echo "✗ Connectivity after cleanup: BROKEN" >> $LOG
        CLEANUP_STATE="BROKEN"
      fi
      
      echo "" >> $LOG
      echo "=== SUMMARY ===" >> $LOG
      echo "Initial state:           WORKING" >> $LOG
      echo "Immediate after create:  $IMMEDIATE_STATE" >> $LOG
      echo "Delayed after create:    $DELAYED_STATE" >> $LOG
      [ "$DELAYED_STATE" = "BROKEN" ] && echo "After route restore:     $RESTORED_STATE" >> $LOG
      echo "After cleanup:           $CLEANUP_STATE" >> $LOG
      
      echo "" >> $LOG
      echo "=== RECOMMENDATIONS ===" >> $LOG
      
      if [ "$IMMEDIATE_STATE" = "BROKEN" ]; then
        echo "- Interface creation immediately breaks connectivity" >> $LOG
        echo "- This suggests systemd-networkd interference" >> $LOG
        echo "- Try adding ignore rules for veth interfaces" >> $LOG
      elif [ "$DELAYED_STATE" = "BROKEN" ]; then
        echo "- Connectivity breaks after a delay" >> $LOG
        echo "- This suggests asynchronous systemd-networkd reconfiguration" >> $LOG
        echo "- Try restarting systemd-networkd before creating interfaces" >> $LOG
      fi
      
      if [ "$DELAYED_STATE" = "BROKEN" ] && [ "$RESTORED_STATE" = "WORKING" ]; then
        echo "- Route restoration fixes the issue" >> $LOG
        echo "- The route is being deleted/modified by systemd-networkd" >> $LOG
        echo "- PreferredSource configuration might help" >> $LOG
      fi
      
      echo "" >> $LOG
      echo "=====================================================" >> $LOG
      echo "Debug complete. Check systemd-networkd ignore rules." >> $LOG
      echo "=====================================================" >> $LOG
    '';
    
    preStop = ''
      # Ensure cleanup even if script fails
      ${pkgs.iproute2}/bin/ip link delete veth0 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link delete veth1 2>/dev/null || true
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
