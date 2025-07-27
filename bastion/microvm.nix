{ self, ... }:
let
  # List of VMs you want to manage on this host
  managedVMs = [
    "sni-proxy"
  ];

  # VMs you want to start automatically
  autostartVMs = [
    "sni-proxy" # Always start the proxy
  ];
in {
  microvm = {
    autostart = autostartVMs;

    # Generate VM configs automatically
    vms = builtins.listToAttrs (map (vmName: {
      name = vmName;
      value = {
        # Host build-time reference to where the MicroVM NixOS is defined
        # under nixosConfigurations
        flake = self;
        # Specify from where to let `microvm -u` update later on
        updateFlake = "git+file:///etc/nixos";
      };
    }) managedVMs);

    stateDir = "/var/lib/microvms";
  };
}
