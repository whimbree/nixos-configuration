{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };
in {
  microvm = {
    mem = 4096;
    hotplugMem = 8192;
    vcpu = 20;

    # Share VPN config from host
    shares = [
      {
        source = "/microvms/jellyfin2/var/lib/jellyfin";
        mountPoint = "/var/lib/jellyfin";
        tag = "jellyfin";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
      }
      {
        source = "/merged/media/shows";
        mountPoint = "/media/shows";
        tag = "media-shows";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/movies";
        mountPoint = "/media/movies";
        tag = "media-movies";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/music";
        mountPoint = "/media/music";
        tag = "media-music";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/books";
        mountPoint = "/media/books";
        tag = "media-books";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
      {
        source = "/merged/media/xxx";
        mountPoint = "/media/xxx";
        tag = "media-xxx";
        proto = "virtiofs";
        securityModel = "mapped-xattr";
        readOnly = true;
      }
    ];

    volumes = [{
      image = "jellyfin-cache.img";
      mountPoint = "/var/cache/jellyfin";
      size = 1024 * 100; # 100GB cache
      fsType = "ext4";
      autoCreate = true;
    }];
  };

  boot.kernelParams = [ "mitigations=off" ];

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # create fileshare user for services
  users.users.fileshare = {
    createHome = false;
    isSystemUser = true;
    group = "fileshare";
    uid = 1420;
  };
  users.groups.fileshare = {
    gid = 1420;
    members = [ "fileshare" ];
  };

  services.jellyfin = {
    enable = true;
    dataDir = "/var/lib/jellyfin";
    cacheDir = "/var/cache/jellyfin";
    user = "fileshare";
    group = "fileshare";
  };

  environment.systemPackages = with pkgs; [
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
  ];

  # Override firewall to allow Jellyfin
  networking.firewall.allowedTCPPorts = [ 8096 ];
}
