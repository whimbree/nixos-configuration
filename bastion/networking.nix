{ lib, pkgs, ... }:
let
  maxTiers = 4; # 0-3
  maxVMsPerTier = 20; # 0-19
in {
  networking = {
    useNetworkd = true;
    firewall = {
      enable = true;
      extraCommands = ''
        iptables -t nat -A POSTROUTING -s 10.0.0.0/20 -o enp1s0 -j MASQUERADE

        # Default: drop inter-tier traffic
        iptables -A FORWARD -s 10.0.0.0/20 -d 10.0.0.0/20 -j DROP

        # Allow T0 (10.0.0.x) to reach all tiers
        iptables -I FORWARD -s 10.0.0.0/24 -d 10.0.0.0/20 -j ACCEPT

        # Allow all tiers to reach T0
        iptables -I FORWARD -s 10.0.0.0/20 -d 10.0.0.0/24 -j ACCEPT

        # Allow established connections back
        iptables -I FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
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
    after = [ "network.target" "microvm@gateway.service" ];
    requires = [ "microvm@gateway.service" ];
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

      # DNAT incoming connections to bastion:80 → gateway:80
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 80 \
        -j DNAT --to-destination $GATEWAY_IP:80
      # SNAT so replies come back through bastion
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING \
        -p tcp -d $GATEWAY_IP --dport 80 \
        -j MASQUERADE
      # Allow forwarding
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $GATEWAY_IP --dport 80 \
        -j ACCEPT

      # DNAT incoming connections to bastion:443 → gateway:443
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 443 \
        -j DNAT --to-destination $GATEWAY_IP:443
      # SNAT so replies come back through bastion
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING \
        -p tcp -d $GATEWAY_IP --dport 443 \
        -j MASQUERADE
      # Allow forwarding
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $GATEWAY_IP --dport 443 \
        -j ACCEPT

      echo "Port forward bastion:443 → gateway:443 configured"
    '';
  };

  systemd.services.forward-airvpn-usa-socks = {
    description = "Forward bastion:4949 to airvpn-usa:1080 SOCKS proxy";
    after = [ "network.target" "microvm@airvpn-usa.service" ];
    requires = [ "microvm@airvpn-usa.service" ];
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

      # DNAT incoming connections to bastion:4949 → airvpn-usa:1080
      ${pkgs.iptables}/bin/iptables -t nat -A PREROUTING \
        -p tcp --dport 4949 \
        -j DNAT --to-destination $AIRVPN_USA_IP:1080

      # SNAT so replies come back through bastion
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING \
        -p tcp -d $AIRVPN_USA_IP --dport 1080 \
        -j MASQUERADE

      # Allow forwarding
      ${pkgs.iptables}/bin/iptables -A FORWARD \
        -p tcp -d $AIRVPN_USA_IP --dport 1080 \
        -j ACCEPT

      echo "Port forward bastion:4949 → airvpn-usa:1080 configured"
    '';
  };
}
