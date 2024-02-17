{ config, pkgs, lib, ... }: {

  # Persist these paths across boots
  fileSystems."/etc/nixos" = {
    device = "/home/bree/nixos-configuration";
    options = [ "bind" ];
  };
  fileSystems."/etc/ssh" = {
    device = "/persist/etc/ssh";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/tailscale" = {
    device = "/persist/var/lib/tailscale";
    options = [ "bind" ];
  };
  fileSystems."/var/db/sudo" = {
    device = "/persist/var/db/sudo";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/cni" = {
    device = "/persist/var/lib/cni";
    options = [ "bind" ];
  };
    fileSystems."/var/lib/machines" = {
    device = "/persist/var/lib/machines";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/containers" = {
    device = "/persist/var/lib/containers";
    options = [ "bind" ];
  };
  fileSystems."/root" = {
    device = "/persist/root";
    options = [ "bind" ];
  };

  # loginctl-linger -- this enables “lingering” for selected users
  # inspired by the discussion (and linked code) in https://github.com/NixOS/nixpkgs/issues/3702
  # this should just be a NixOS option really
  fileSystems."/var/lib/systemd/linger" = {
    device = "/persist/var/lib/systemd/linger";
    options = [ "bind" ];
  };

  # machine-id is used by systemd for the journal
  # this allows to use journalctl to look at journals for previous boots
  environment.etc."machine-id".source = "/persist/etc/machine-id";

  # kernel modules are exposed at /lib/modules
  fileSystems."/lib/modules" = {
    device = "/run/booted-system/kernel-modules/lib/modules";
    options = [ "bind" ];
  };

}
