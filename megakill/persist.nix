{ config, pkgs, lib, ... }: {

  # Persist these paths across boots
  fileSystems."/etc/nixos" = {
    device = "/home/bree/nixos-configuration";
    fsType = "none";
    options = [ "bind" ];
  };

}
