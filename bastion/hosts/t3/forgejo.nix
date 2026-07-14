{ lib, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };
in {
  microvm = {
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;

    shares = [{
      source = "/microvms/forgejo/var/lib/forgejo";
      mountPoint = "/var/lib/forgejo";
      tag = "forgejo-data";
      proto = "virtiofs";
      securityModel = "mapped-xattr";
    }];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  services.forgejo = {
    enable = true;
    # sqlite lives on the virtiofs share; virtiofsd runs with --allow-mmap
    # (microvm-defaults.nix) so mmap-based DB access works.
    database.type = "sqlite3";
    lfs.enable = true;

    settings = {
      server = {
        DOMAIN = "git.bspwr.com";
        ROOT_URL = "https://git.bspwr.com/";
        HTTP_ADDR = "0.0.0.0";
        HTTP_PORT = 3000;

        # Built-in SSH server on 2222; port 22 stays with the VM's admin sshd.
        # Exposed externally via DNAT on bastion (forward-forgejo-ssh in
        # bastion/networking.nix): git.bspwr.com:2222 → this VM's 2222.
        START_SSH_SERVER = true;
        SSH_DOMAIN = "git.bspwr.com";
        SSH_LISTEN_HOST = "0.0.0.0";
        SSH_LISTEN_PORT = 2222;
        SSH_PORT = 2222;
      };

      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;

      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "https://code.forgejo.org";
      };
    };
  };

  # HTTP UI/API + built-in git SSH
  networking.firewall.allowedTCPPorts = [ 3000 2222 ];
}
