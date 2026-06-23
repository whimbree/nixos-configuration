{ pkgs, ... }: {
  fileSystems."/" = {
    device = "rpool/local/root";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/nix" = {
    device = "rpool/local/nix";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/var/log" = {
    device = "rpool/local/log";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/blockchain" = {
    device = "rpool/local/blockchain";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "rpool/safe/home";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/persist" = {
    device = "rpool/safe/persist";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/services" = {
    device = "rpool/safe/services";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/services/jellyfin" = {
    device = "rpool/safe/services/jellyfin";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/services/nextcloud" = {
    device = "rpool/safe/services/nextcloud";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/services/immich" = {
    device = "rpool/safe/services/immich";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/airvpn-sweden" = {
    device = "rpool/safe/microvms/airvpn-sweden";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/airvpn-usa" = {
    device = "rpool/safe/microvms/airvpn-usa";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/airvpn-switzerland" = {
    device = "rpool/safe/microvms/airvpn-switzerland";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/jellyfin" = {
    device = "rpool/safe/microvms/jellyfin";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/microvms/navidrome" = {
    device = "rpool/safe/microvms/navidrome";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/var/lib/microvms" = {
    device = "rpool/safe/microvm-runtime";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/97E0-36CE";
    fsType = "vfat";
    neededForBoot = true;
  };

  fileSystems."/ocean/nas/bree" = {
    device = "ocean/nas/bree";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/downloads" = {
    device = "ocean/downloads";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/media" = {
    device = "ocean/media";
    fsType = "zfs";
    neededForBoot = true;
    options = [ "nofail" ];
  };

  fileSystems."/ocean/files" = {
    device = "ocean/files";
    fsType = "zfs";
    neededForBoot = true;
    options = [ "nofail" ];
  };

  fileSystems."/neptune/media" = {
    device = "neptune/media";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/public" = {
    device = "ocean/public";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/services" = {
    device = "ocean/services";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/services/immich" = {
    device = "ocean/services/immich";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/services/nextcloud" = {
    device = "ocean/services/nextcloud";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/services/fluxer" = {
    device = "rpool/safe/services/fluxer";
    fsType = "zfs";
    neededForBoot = true;
  };

  fileSystems."/ocean/images" = {
    device = "ocean/images";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/overkill" = {
    device = "ocean/backup/overkill";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  fileSystems."/ocean/backup/duplicati" = {
    device = "ocean/backup/duplicati";
    fsType = "zfs";
    options = [ "nofail" ];
    neededForBoot = true;
  };

  environment.systemPackages = with pkgs; [ mergerfs ];
  fileSystems."/merged/media" = {
    fsType = "fuse.mergerfs";
    depends = [ "/ocean/media" "/neptune/media" ];
    device = "/ocean/media:/neptune/media";
    options = [
      "nofail"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"
    ];
  };
}
