# bastion/microvm.nix
{ lib, ... }:
let
  # Import VM library with all the logic
  vmLib = import ./lib/vm-lib.nix { inherit lib; };

  # The registry is the source of truth - files MUST exist or we crash!
  # Verify all registered VMs have corresponding config files
  verifyVMFiles = lib.mapAttrs (vmName: vmConfig:
    let
      expectedPath = ./hosts + "/t${toString vmConfig.tier}/${vmName}.nix";
      fileExists = builtins.pathExists expectedPath;
    in if !fileExists then
      throw
      "VM '${vmName}' is registered but missing config file: ${toString expectedPath}"
    else
      vmConfig) vmLib.getAllVMs;

  registeredVMNames = builtins.attrNames verifyVMFiles;
  autostartVMNames = builtins.attrNames (
    lib.filterAttrs (_name: vmConfig: vmConfig.autostart) verifyVMFiles
  );

in {
  microvm = {
    # The VM runners are managed imperatively in /var/lib/microvms. Keeping
    # only the autostart names here prevents a bastion rebuild from pulling
    # every guest runner and EROFS store disk into the host system closure.
    #
    # Create a new VM once with `microvm -c <name>`, then update it explicitly
    # with `microvm -uR <name>`. Existing installed profiles remain untouched.
    autostart = autostartVMNames;
    stateDir = "/var/lib/microvms";
  };

  # Declaratively deployed VMs did not receive the GC roots normally created
  # by `microvm -c`. Once their runners are decoupled from the host closure,
  # these indirect roots keep both the selected and currently booted profiles
  # alive across Nix garbage collection. Missing (not-yet-created) VMs are
  # intentionally skipped.
  system.activationScripts."microvm-gc-roots".text = ''
    install -d -m 0755 /nix/var/nix/gcroots/microvm
    ${lib.concatMapStringsSep "\n" (vmName: ''
      if [ -L "/var/lib/microvms/${vmName}/current" ]; then
        ln -sfn "/var/lib/microvms/${vmName}/current" \
          "/nix/var/nix/gcroots/microvm/${vmName}"
        # Match `microvm -c`: create this indirection even before `booted`
        # exists. VM startup fills that symlink, keeping the running (possibly
        # pre-update) runner rooted after `current` advances.
        ln -sfn "/var/lib/microvms/${vmName}/booted" \
          "/nix/var/nix/gcroots/microvm/booted-${vmName}"
      fi
    '') registeredVMNames}
  '';

  # # Explicitly mask services that shouldn't autostart
  # systemd.services = lib.listToAttrs (map (vmName: {
  #   name = "microvm@${vmName}";
  #   value.enable = false;  # or try setting serviceConfig.ExecStart = "";
  # }) noAutostartVMs);

  # Auto-generate /etc/hosts entries for ALL registered VMs
  networking.hosts = vmLib.mkHostsEntries vmLib.getAllVMs;

  # Secrets directory for VMs
  systemd.tmpfiles.rules = [ "d /var/lib/microvm-secrets 0700 root root -" ];
}
