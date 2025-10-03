{ lib, ... }:
let
  maxTiers = 5; # 0-4
  maxVMsPerTier = 20; # 0-19
in {
  networking = {
    useNetworkd = true;
    firewall = {
      enable = true;
      extraCommands = ''
        iptables -t nat -A POSTROUTING -s 10.0.0.0/20 -o enp1s0 -j MASQUERADE
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
