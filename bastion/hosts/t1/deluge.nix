{ lib, pkgs, mkVMNetworking, ... }:
let
  # Import VM registry to get our config
  vmRegistry = import ../../vm-registry.nix;
  vmConfig = vmRegistry.vms.deluge;

  # Generate networking from registry data
  networking = mkVMNetworking { 
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };
in {
  microvm = {
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;
  };

  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # Override firewall to allow HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 22 80 ];
}
