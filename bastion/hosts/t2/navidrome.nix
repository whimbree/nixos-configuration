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
    mem = 512;
    hotplugMem = 512;
    vcpu = 2;

    shares = [
      {
        source = "/microvms/navidrome/var/lib/navidrome";
        mountPoint = "/var/lib/navidrome";
        tag = "navidrome-data";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/merged/media/music";
        mountPoint = "/media/music";
        tag = "media-music";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  services.navidrome = {
    enable = true;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = "/media/music";
      DataFolder = "/var/lib/navidrome";
      LogLevel = "info";
      ScanSchedule = "@every 15m";
      TranscodingCacheSize = "1GB";
      ImageCacheSize = "500MB";
    };
  };

  networking.firewall.allowedTCPPorts = [ 4533 ];
}
