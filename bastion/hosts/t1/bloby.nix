{ lib, pkgs, vmName, mkVMNetworking, ... }:
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

    # Override defaults: single persistent root, no separate ssh-host-keys volume
    volumes = lib.mkForce [{
      image = "root.img";
      mountPoint = "/";
      size = 1024 * 50; # 50GB
      fsType = "ext4";
      autoCreate = true;
    }];
  };

  # mkOverride 10 beats the mkForce (priority 50) tmpfs root in microvm-defaults.nix
  fileSystems."/" = lib.mkOverride 10 {
    device = "/dev/vda";
    fsType = "ext4";
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # nix-ld provides /lib64/ld-linux-x86-64.so.2 so prebuilt binaries
  # from npm (esbuild, sharp, better-sqlite3, etc.) can run on NixOS
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    nodejs_22
    python3
    gnumake
    gcc
  ];

  environment.variables = {
    NPM_CONFIG_PREFIX = "/var/lib/bloby/npm-global";
  };

  environment.sessionVariables = {
    PATH = [ "/var/lib/bloby/npm-global/bin" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/bloby/npm-global 0755 admin users -"
  ];

  networking.firewall = {
    allowedTCPPorts = [ 22 80 443 ];
  };
}
