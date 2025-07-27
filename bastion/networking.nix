{ lib, ... }:
let 
  # Generate routes for all tiers: 10.0.0.x through 10.0.9.x
  maxTiers = 5;   # 0-4 
  maxVMsPerTier = 20;  # 0-99 per tier
in {
  networking.useNetworkd = true;

  systemd.network.networks = builtins.listToAttrs (
    # Generate all combinations of tier.vm
    lib.flatten (map (tier:
      map (vm: {
        name = "30-vm${toString tier}-${toString vm}";
        value = {
          matchConfig.Name = "vm${toString (tier * 100 + vm)}";  # Unique interface names
          address = [ "10.0.0.0/32" ];
          routes = [{ 
            Destination = "10.0.${toString tier}.${toString vm}/32"; 
          }];
          networkConfig = { IPv4Forwarding = true; };
        };
      }) (lib.genList (i: i) maxVMsPerTier)  # 0-98
    ) (lib.genList (i: i) maxTiers))  # 0-9
  );
}
