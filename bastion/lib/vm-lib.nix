# bastion/lib/vm-lib.nix - All VM calculation logic in one place
{ lib }:
let
  # Import raw registry data
  vmRegistry = import ../vm-registry.nix;

  # VM calculation functions
  vmLib = {
    # Calculate IP from tier and index
    mkIP = { tier, index }: "10.0.${toString tier}.${toString index}";

    # Calculate MAC from tier and index  
    mkMAC = { tier, index }:
      "02:00:00:${lib.fixedWidthString 2 "0" (lib.toHexString tier)}:00:${
        lib.fixedWidthString 2 "0" (lib.toHexString index)
      }";

    # Calculate interface ID from tier and index
    mkInterfaceID = { tier, index }: "vm${toString (tier * 100 + index)}";

    # Enrich a VM config with calculated fields
    enrichVMConfig = vmConfig:
      vmConfig // {
        ip = vmLib.mkIP { inherit (vmConfig) tier index; };
        mac = vmLib.mkMAC { inherit (vmConfig) tier index; };
        interfaceID = vmLib.mkInterfaceID { inherit (vmConfig) tier index; };
      };

    # Get enriched VM config by name
    getVM = vmName: vmLib.enrichVMConfig vmRegistry.vms.${vmName};

    # Get all VMs with enriched data
    getAllVMs =
      lib.mapAttrs (name: config: vmLib.enrichVMConfig config) vmRegistry.vms;

    # Filter VMs by criteria
    getVMsByTier = tier:
      lib.filterAttrs (name: vm: vm.tier == tier) vmLib.getAllVMs;
    getVMsToAutostart =
      lib.filterAttrs (name: vm: vm.autostart) vmLib.getAllVMs;

    # Generate /etc/hosts entries
    mkHostsEntries = vms:
      lib.mapAttrs (name: vm: [ vm.hostname ])
      (lib.mapAttrs (name: vm: vm.ip) vms);
  };
in vmLib
