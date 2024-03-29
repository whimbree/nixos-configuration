{ config, pkgs, lib, ... }: {
  # Persist these paths across boots
  fileSystems."/etc/nixos" = {
    device = "/home/bree/nixos-configuration";
    options = [ "bind" ];
  };
  fileSystems."/etc/cockpit" = {
    device = "/persist/etc/cockpit";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/samba" = {
    device = "/persist/var/lib/samba";
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
  fileSystems."/var/lib/lxc" = {
    device = "/persist/var/lib/lxc";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/lxd" = {
    device = "/persist/var/lib/lxd";
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
  fileSystems."/var/lib/clamav" = {
    device = "/persist/var/lib/clamav";
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

  # persist SSH host keys
  environment.etc."ssh/ssh_host_rsa_key".source =
    "/persist/etc/ssh/ssh_host_rsa_key";
  environment.etc."ssh/ssh_host_rsa_key.pub".source =
    "/persist/etc/ssh/ssh_host_rsa_key.pub";
  environment.etc."ssh/ssh_host_ed25519_key".source =
    "/persist/etc/ssh/ssh_host_ed25519_key";
  environment.etc."ssh/ssh_host_ed25519_key.pub".source =
    "/persist/etc/ssh/ssh_host_ed25519_key.pub";

  # kernel modules are exposed at /lib/modules
  fileSystems."/lib/modules" = {
    device = "/run/booted-system/kernel-modules/lib/modules";
    options = [ "bind" ];
  };
}
