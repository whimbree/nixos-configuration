{ lib, ... }:
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
}
