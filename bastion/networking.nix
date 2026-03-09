{ config, lib, pkgs, ... }:
let
  maxTiers = 4; # 0-3
  maxVMsPerTier = 20; # 0-19
in {
  networking = {
    useNetworkd = true;
    firewall = {
      enable = true;
      extraCommands = ''
        # Flush stale NAT/FORWARD rules from previous runs before re-adding
        # Without this, nixos-rebuild appends duplicates and old service rules persist
        iptables -t nat -F PREROUTING
        iptables -t nat -F POSTROUTING
        iptables -F FORWARD

        # Set default forward policy to DROP (secure by default)
        iptables -P FORWARD DROP

        # Allow return traffic to hypervisor for connections it initiated
        iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

        # Allow NFS from VMs specifically
        iptables -I INPUT -s 10.0.0.0/20 -p tcp --dport 2049 -j ACCEPT

        # Block VMs from accessing the hypervisor itself (new connections only)
        iptables -A INPUT -s 10.0.0.0/20 -j DROP

        # NAT: Masquerade all VM traffic going out to the internet via enp1s0
        # This makes VM traffic appear to come from the hypervisor's IP
        iptables -t nat -A POSTROUTING -s 10.0.0.0/20 -o enp1s0 -j MASQUERADE

        # Allow return traffic for connections that VMs initiated
        # This is for responses from internet, T0, etc. - checked first for performance
        iptables -I FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

        # Allow T0 gateway tier (10.0.0.x) to reach any VM in any tier
        # Gateway VMs can initiate connections to all other VMs
        iptables -I FORWARD -s 10.0.0.0/24 -d 10.0.0.0/20 -j ACCEPT

        # Allow any VM in any tier to reach T0 gateway tier
        iptables -I FORWARD -s 10.0.0.0/20 -d 10.0.0.0/24 -j ACCEPT

        # Allow webrtc VM (T1) to reach fluxer (T3) for LiveKit webhooks
        iptables -I FORWARD -s 10.0.1.5 -d 10.0.3.7 -p tcp --dport 8080 -j ACCEPT

        # Block all VM traffic destined for the 192.168.0.0/16 private network
        iptables -A FORWARD -d 192.168.0.0/16 -j DROP

        # Allow VMs to send traffic out to the internet (via enp1s0)
        # This permits outbound internet connections from all VMs
        iptables -A FORWARD -s 10.0.0.0/20 -o enp1s0 -j ACCEPT

        # Default: block all direct VM-to-VM traffic (inter-tier and intra-tier)
        # Forces cross-VM communication to go through T0 gateway tier
        # This rule is checked last, so allowed traffic (T0, internet, established) bypasses it
        iptables -A FORWARD -s 10.0.0.0/20 -d 10.0.0.0/20 -j DROP
      '';
    };
  };

  systemd.network.networks = builtins.listToAttrs (
    # Generate all combinations of tier.vm
    lib.flatten (map (tier:
      map (vm: {
        name = "30-vm${toString tier}-${toString vm}";
        value = {
          matchConfig.Name =
            "vm${toString (tier * 100 + vm)}"; # Unique interface names
          address = [ "10.0.0.0/32" ];
          routes =
            [{ Destination = "10.0.${toString tier}.${toString vm}/32"; }];
          networkConfig = { IPv4Forwarding = true; };
        };
      }) (lib.genList (i: i) maxVMsPerTier)) (lib.genList (i: i) maxTiers)));

  systemd.services.forward-http-gateway = {
    description = "Forward bastion:80|443 to gateway:80|443";
    after = [ "firewall.service" "network.target" "microvm@gateway.service" ];
    requires = [ "microvm@gateway.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Resolve gateway to IP address
      GATEWAY_IP=$(${pkgs.gawk}/bin/awk '/gateway/ {print $1; exit}' /etc/hosts)

      if [ -z "$GATEWAY_IP" ]; then
        echo "ERROR: Could not resolve gateway from /etc/hosts"
        exit 1
      fi

      echo "Resolved gateway to $GATEWAY_IP"

      # DNAT: Rewrite destination of incoming packets from external interface
      # Traffic from internet:80 → bastion:80 gets rewritten to → gateway:80
      # Source IP is preserved at this stage (e.g., 203.0.113.5 stays 203.0.113.5)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 \
        -p tcp --dport 80 \
        -j DNAT --to-destination $GATEWAY_IP:80
      
      # NO MASQUERADE for port 80!
      # Since gateway's default route is back through bastion (via 10.0.0.0),
      # return packets will naturally flow: gateway → bastion → internet
      # This preserves the real client IP so nginx sees it
      
      # Allow forwarding of packets to gateway
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $GATEWAY_IP --dport 80 \
        -j ACCEPT

      # Allow forwarding of return packets from gateway back out
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $GATEWAY_IP --sport 80 \
        -j ACCEPT

      # DNAT: Same for HTTPS traffic
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 \
        -p tcp --dport 443 \
        -j DNAT --to-destination $GATEWAY_IP:443
      
      # NO MASQUERADE for port 443 either!
      # Return path: gateway → bastion → internet (via gateway's default route)
      
      # Allow forwarding to gateway
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $GATEWAY_IP --dport 443 \
        -j ACCEPT

      # Allow forwarding of return packets from gateway
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $GATEWAY_IP --sport 443 \
        -j ACCEPT

      echo "Port forward bastion:443 → gateway:443 configured (preserving source IPs)"
    '';
  };

  systemd.services.forward-airvpn-usa-socks = {
    description = "Forward bastion:4949 to airvpn-usa:1080 SOCKS proxy";
    after = [ "firewall.service" "network.target" "microvm@airvpn-usa.service" ];
    requires = [ "microvm@airvpn-usa.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Resolve airvpn-usa to IP address
      AIRVPN_USA_IP=$(${pkgs.gawk}/bin/awk '/airvpn-usa/ {print $1; exit}' /etc/hosts)

      if [ -z "$AIRVPN_USA_IP" ]; then
        echo "ERROR: Could not resolve airvpn-usa from /etc/hosts"
        exit 1
      fi

      echo "Resolved airvpn-usa to $AIRVPN_USA_IP"

      # DNAT: Rewrite incoming connections from bastion:4949 → airvpn-usa:1080
      # Preserves source IP so SOCKS proxy can see real client addresses
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 4949 \
        -j DNAT --to-destination $AIRVPN_USA_IP:1080

      # NO MASQUERADE - let airvpn-usa see the real client IP
      # Return packets: airvpn-usa → bastion → client (via airvpn-usa's default route)

      # Allow forwarding to airvpn-usa
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $AIRVPN_USA_IP --dport 1080 \
        -j ACCEPT

      # Allow return packets from airvpn-usa
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $AIRVPN_USA_IP --sport 1080 \
        -j ACCEPT

      echo "Port forward bastion:4949 → airvpn-usa:1080 configured (preserving source IPs)"
    '';
  };

  systemd.services.forward-airvpn-sweden-socks = {
    description = "Forward bastion:5151 to airvpn-sweden:1080 SOCKS proxy";
    after = [ "firewall.service" "network.target" "microvm@airvpn-sweden.service" ];
    requires = [ "microvm@airvpn-sweden.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Resolve airvpn-sweden to IP address
      AIRVPN_SWEDEN_IP=$(${pkgs.gawk}/bin/awk '/airvpn-sweden/ {print $1; exit}' /etc/hosts)

      if [ -z "$AIRVPN_SWEDEN_IP" ]; then
        echo "ERROR: Could not resolve airvpn-sweden from /etc/hosts"
        exit 1
      fi

      echo "Resolved airvpn-sweden to $AIRVPN_SWEDEN_IP"

      # DNAT: Rewrite incoming connections from bastion:5151 → airvpn-sweden:1080
      # Preserves source IP so SOCKS proxy can see real client addresses
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 5151 \
        -j DNAT --to-destination $AIRVPN_SWEDEN_IP:1080

      # NO MASQUERADE - let airvpn-sweden see the real client IP
      # Return packets: airvpn-sweden → bastion → client (via airvpn-sweden's default route)

      # Allow forwarding to airvpn-sweden
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $AIRVPN_SWEDEN_IP --dport 1080 \
        -j ACCEPT

      # Allow return packets from airvpn-sweden
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $AIRVPN_SWEDEN_IP --sport 1080 \
        -j ACCEPT

      echo "Port forward bastion:5151 → airvpn-sweden:1080 configured (preserving source IPs)"
    '';
  };

  systemd.services.forward-airvpn-switzerland-socks = {
    description = "Forward bastion:5252 to airvpn-switzerland:1080 SOCKS proxy";
    after = [ "firewall.service" "network.target" "microvm@airvpn-switzerland.service" ];
    requires = [ "microvm@airvpn-switzerland.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Resolve airvpn-switzerland to IP address
      AIRVPN_SWITZERLAND_IP=$(${pkgs.gawk}/bin/awk '/airvpn-switzerland/ {print $1; exit}' /etc/hosts)

      if [ -z "$AIRVPN_SWITZERLAND_IP" ]; then
        echo "ERROR: Could not resolve airvpn-switzerland from /etc/hosts"
        exit 1
      fi

      echo "Resolved airvpn-switzerland to $AIRVPN_SWITZERLAND_IP"

      # DNAT: Rewrite incoming connections from bastion:5252 → airvpn-switzerland:1080
      # Preserves source IP so SOCKS proxy can see real client addresses
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 5252 \
        -j DNAT --to-destination $AIRVPN_SWITZERLAND_IP:1080

      # NO MASQUERADE - let airvpn-switzerland see the real client IP
      # Return packets: airvpn-switzerland → bastion → client (via airvpn-switzerland's default route)

      # Allow forwarding to airvpn-switzerland
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $AIRVPN_SWITZERLAND_IP --dport 1080 \
        -j ACCEPT

      # Allow return packets from airvpn-switzerland
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $AIRVPN_SWITZERLAND_IP --sport 1080 \
        -j ACCEPT

      echo "Port forward bastion:5252 → airvpn-switzerland:1080 configured (preserving source IPs)"
    '';
  };

  systemd.services.forward-airvpn-switzerland-monero = {
    description = "Forward bastion:18089 to airvpn-switzerland:46279 monero rpc";
    after = [ "firewall.service" "network.target" "microvm@airvpn-switzerland.service" ];
    requires = [ "microvm@airvpn-switzerland.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      # Resolve airvpn-switzerland to IP address
      AIRVPN_SWITZERLAND_IP=$(${pkgs.gawk}/bin/awk '/airvpn-switzerland/ {print $1; exit}' /etc/hosts)

      if [ -z "$AIRVPN_SWITZERLAND_IP" ]; then
        echo "ERROR: Could not resolve airvpn-switzerland from /etc/hosts"
        exit 1
      fi

      echo "Resolved airvpn-switzerland to $AIRVPN_SWITZERLAND_IP"

      # DNAT: Rewrite incoming connections from bastion:18089 → airvpn-switzerland:46279
      # Preserves source IP so SOCKS proxy can see real client addresses
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 18089 \
        -j DNAT --to-destination $AIRVPN_SWITZERLAND_IP:46279

      # NO MASQUERADE - let airvpn-switzerland see the real client IP
      # Return packets: airvpn-switzerland → bastion → client (via airvpn-switzerland's default route)

      # Allow forwarding to airvpn-switzerland
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $AIRVPN_SWITZERLAND_IP --dport 46279 \
        -j ACCEPT

      # Allow return packets from airvpn-switzerland
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $AIRVPN_SWITZERLAND_IP --sport 46279 \
        -j ACCEPT

      echo "Port forward bastion:18089 → airvpn-switzerland:46279 configured (preserving source IPs)"
    '';
  };

  systemd.services.forward-webrtc-coturn = {
    description = "Forward TURN ports to webrtc microvm";
    after = [ "firewall.service" "network.target" "microvm@webrtc.service" ];
    requires = [ "microvm@webrtc.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      WEBRTC_IP=$(${pkgs.gawk}/bin/awk '/webrtc/ {print $1; exit}' /etc/hosts)

      if [ -z "$WEBRTC_IP" ]; then
        echo "ERROR: Could not resolve webrtc from /etc/hosts"
        exit 1
      fi

      echo "Resolved webrtc to $WEBRTC_IP"

      # TURN/STUN UDP (3478)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 -p udp --dport 3478 \
        -j DNAT --to-destination $WEBRTC_IP:3478

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -d $WEBRTC_IP --dport 3478 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -s $WEBRTC_IP --sport 3478 -j ACCEPT

      # TURN/STUN TCP (3478)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 -p tcp --dport 3478 \
        -j DNAT --to-destination $WEBRTC_IP:3478

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $WEBRTC_IP --dport 3478 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $WEBRTC_IP --sport 3478 -j ACCEPT

      # TURN TLS TCP (5349)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 -p tcp --dport 5349 \
        -j DNAT --to-destination $WEBRTC_IP:5349

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $WEBRTC_IP --dport 5349 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $WEBRTC_IP --sport 5349 -j ACCEPT

      # TURN DTLS UDP (5349)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 -p udp --dport 5349 \
        -j DNAT --to-destination $WEBRTC_IP:5349

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -d $WEBRTC_IP --dport 5349 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -s $WEBRTC_IP --sport 5349 -j ACCEPT

      # coturn relay port range (50000-51999)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 -p udp --dport 50000:51999 \
        -j DNAT --to-destination $WEBRTC_IP

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -d $WEBRTC_IP --dport 50000:51999 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -s $WEBRTC_IP --sport 50000:51999 -j ACCEPT

      echo "Port forward TURN (3478/udp+tcp, 5349/udp+tcp, 50000-51999/udp) → webrtc configured"
    '';
  };

  systemd.services.forward-webrtc-livekit = {
    description = "Forward LiveKit media ports to webrtc microvm";
    after = [ "firewall.service" "network.target" "microvm@webrtc.service" ];
    requires = [ "microvm@webrtc.service" ];
    partOf = [ "firewall.service" ];
    restartTriggers = [ config.networking.firewall.extraCommands ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      WEBRTC_IP=$(${pkgs.gawk}/bin/awk '/webrtc/ {print $1; exit}' /etc/hosts)

      if [ -z "$WEBRTC_IP" ]; then
        echo "ERROR: Could not resolve webrtc from /etc/hosts"
        exit 1
      fi

      echo "Resolved webrtc to $WEBRTC_IP"

      # LiveKit ICE TCP (7881)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 \
        -p tcp --dport 7881 \
        -j DNAT --to-destination $WEBRTC_IP:7881

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $WEBRTC_IP --dport 7881 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -s $WEBRTC_IP --sport 7881 -j ACCEPT

      # LiveKit RTP media UDP (52000-53999)
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -i enp1s0 \
        -p udp --dport 52000:53999 \
        -j DNAT --to-destination $WEBRTC_IP

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -d $WEBRTC_IP --dport 52000:53999 -j ACCEPT

      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p udp -s $WEBRTC_IP --sport 52000:53999 -j ACCEPT

      echo "Port forward LiveKit media (7881/tcp, 52000-53999/udp) → webrtc configured"
    '';
  };
}
