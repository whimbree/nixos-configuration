# bastion/microvm.nix
{ self, lib, ... }:
let
  # Import VM library with all the logic
  vmLib = import ./lib/vm-lib.nix { inherit lib; };

  # The registry is the source of truth - files MUST exist or we crash!
  allVMs = vmLib.getAllVMs;

  # Verify all registered VMs have corresponding config files
  verifyVMFiles = lib.mapAttrs (vmName: vmConfig:
    let
      expectedPath = "./hosts/t${toString vmConfig.tier}/${vmName}.nix";
      fileExists = builtins.pathExists expectedPath;
    in if !fileExists then
      throw
      "VM '${vmName}' is registered but missing config file: ${expectedPath}"
    else
      vmConfig) allVMs;

  # Get VMs that should autostart (from registry)
  autostartVMs = lib.mapAttrsToList (name: config: name) vmLib.getVMsToAutostart;

in {
  microvm = {
    # Create services for ALL VMs
    vms = lib.mapAttrs (name: config: {
      flake = self;
      updateFlake = "git+file:///etc/nixos";
    }) verifyVMFiles;

    autostart = autostartVMs;

    stateDir = "/var/lib/microvms";
  };

  # # Explicitly mask services that shouldn't autostart
  # systemd.services = lib.listToAttrs (map (vmName: {
  #   name = "microvm@${vmName}";
  #   value.enable = false;  # or try setting serviceConfig.ExecStart = "";
  # }) noAutostartVMs);

  # Auto-generate /etc/hosts entries for ALL registered VMs
  networking.hosts = vmLib.mkHostsEntries allVMs;

  # Secrets directory for VMs
  systemd.tmpfiles.rules = [ "d /var/lib/microvm-secrets 0700 root root -" ];
}
