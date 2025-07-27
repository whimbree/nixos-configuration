# bastion/microvm.nix
{ self, lib, ... }:
let
  # Import VM library with all the logic
  vmLib = import ./lib/vm-lib.nix { inherit lib; };
  
  # Get all registered VMs
  allRegisteredVMs = vmLib.getAllVMs;
  
  # Only manage VMs that are both registered AND have config files
  managedVMs = lib.filterAttrs (vmName: vmConfig:
    let
      expectedPath = ./hosts/t${toString vmConfig.tier}/${vmName}.nix;
    in
      builtins.pathExists expectedPath
  ) allRegisteredVMs;
  
  # Get VMs that should autostart (from registry, but only if they exist)
  autostartVMs = lib.mapAttrsToList (name: config: name) (
    lib.filterAttrs (name: config: config.autostart) managedVMs
  );
in {
  microvm = {
    autostart = autostartVMs;

    # Generate VM configs for VMs that exist
    vms = lib.mapAttrs (name: config: {
      flake = self;
      updateFlake = "git+file:///etc/nixos";
    }) managedVMs;

    stateDir = "/var/lib/microvms";
  };

  # Auto-generate /etc/hosts entries for managed VMs only
  networking.hosts = vmLib.mkHostsEntries managedVMs;

  # Secrets directory for VMs
  systemd.tmpfiles.rules = [
    "d /var/lib/microvm-secrets 0700 root root -"
  ];
}