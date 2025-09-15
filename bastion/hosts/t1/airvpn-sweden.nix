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
