{ config, pkgs, lib, ... }: {
  # Persist these paths across boots
  fileSystems."/etc/nixos" = {
    device = "/home/bree/nixos-configuration/bastion";
    options = [ "bind" ];
  };
  fileSystems."/etc/cockpit" = {
    device = "/persist/etc/cockpit";
    options = [ "bind" ];
  };
  fileSystems."/var/log" = {
    device = "/persist/var/log";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/nfs" = {
    device = "/persist/var/lib/nfs";
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

  # machine-id is used by systemd for the journal
  # this allows to use journalctl to look at journals for previous boots.
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
}
