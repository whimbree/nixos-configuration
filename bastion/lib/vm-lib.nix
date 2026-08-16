# All VM calculation logic in one place
{ lib }:
let
  # Import raw registry data
  vmRegistry = import ../vm-registry.nix;
  registryDefaults = vmRegistry.defaults or { };
  registeredVMs = vmRegistry.vms or { };

  invalidVMs = lib.filter (name:
    let
      vm = registeredVMs.${name};
      merged = registryDefaults // vm;
    in !(builtins.isAttrs vm)
       || !(builtins.isInt (merged.tier or null))
       || !(builtins.isInt (merged.index or null))
       || !(builtins.isString (merged.hypervisor or null))
       || !(builtins.isBool (merged.observability or null))
       || !(builtins.isBool (merged.rolloutActivated or null)))
    (builtins.attrNames registeredVMs);

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

    # Extract hostname from file path (automatically DRY!)
    mkHostnameFromPath = filePath:
      let
        # Extract filename without .nix extension
        fileName = lib.removeSuffix ".nix" (baseNameOf filePath);
      in fileName;

    # Enrich a VM config with calculated fields
    enrichVMConfig = vmConfig:
      let merged = registryDefaults // vmConfig;
      in merged // {
        ip = vmLib.mkIP { inherit (merged) tier index; };
        mac = vmLib.mkMAC { inherit (merged) tier index; };
        interfaceID = vmLib.mkInterfaceID { inherit (merged) tier index; };
      };

    # Enrich VM config with hostname derived from registry key
    enrichVMConfigWithName = vmName: vmConfig:
      (vmLib.enrichVMConfig vmConfig) // {
        hostname = vmName; # Use the registry key as hostname
      };

    # Get enriched VM config by name
    getVM = vmName:
      assert lib.assertMsg (builtins.hasAttr vmName registeredVMs)
        "Unknown VM in vm-registry.nix: ${vmName}";
      vmLib.enrichVMConfigWithName vmName registeredVMs.${vmName};

    # Get all VMs with enriched data
    getAllVMs =
      lib.mapAttrs (name: config: vmLib.enrichVMConfigWithName name config)
      registeredVMs;

    # Filter VMs by criteria
    getVMsByTier = tier:
      lib.filterAttrs (name: vm: vm.tier == tier) vmLib.getAllVMs;
    getVMsToAutostart =
      lib.filterAttrs (name: vm: vm.autostart) vmLib.getAllVMs;
    getObservedVMs =
      lib.filterAttrs (_name: vm: vm.observability) vmLib.getAllVMs;
    getVMsByHypervisor = hypervisor:
      lib.filterAttrs (_name: vm: vm.hypervisor == hypervisor) vmLib.getAllVMs;

    # Generate /etc/hosts entries as attrset (IP -> [hostname])
    mkHostsEntries = vms:
      lib.mapAttrs' (name: vm: {
        name = vm.ip;
        value = [ vm.hostname ];
      }) vms;
  };
in
assert lib.assertMsg (builtins.isAttrs registryDefaults)
  "vm-registry.nix defaults must be an attribute set";
assert lib.assertMsg (builtins.isString (registryDefaults.hypervisor or null))
  "vm-registry.nix defaults.hypervisor must be a string";
assert lib.assertMsg (builtins.isBool (registryDefaults.observability or null))
  "vm-registry.nix defaults.observability must be a boolean";
assert lib.assertMsg (builtins.isBool (registryDefaults.rolloutActivated or null))
  "vm-registry.nix defaults.rolloutActivated must be a boolean";
assert lib.assertMsg (builtins.isAttrs registeredVMs)
  "vm-registry.nix vms must be an attribute set";
assert lib.assertMsg (invalidVMs == [ ]) ''
  Invalid VM registry entries (tier/index must be integers; hypervisor a
  string; observability/rolloutActivated booleans):
  ${lib.concatStringsSep ", " invalidVMs}
'';
vmLib
