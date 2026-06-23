{ config, pkgs, lib, ... }: {

  # Persist these paths across boots
  fileSystems."/etc/nixos" = {
    device = "/home/bree/nixos-configuration";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/etc/ssh" = {
    device = "/persist/etc/ssh";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/tailscale" = {
    device = "/persist/var/lib/tailscale";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/db/sudo" = {
    device = "/persist/var/db/sudo";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/cni" = {
    device = "/persist/var/lib/cni";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/machines" = {
    device = "/persist/var/lib/machines";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/containers" = {
    device = "/persist/var/lib/containers";
    fsType = "none";
    options = [ "bind" ];
  };
  # UID/GID allocation map for auto-allocated system users (e.g. the static
  # gatus user). With mutableUsers = false this is what keeps their IDs stable
  # across the erase-on-reboot root; without it, persisted data like
  # /services/gatus ends up owned by a stale UID. neededForBoot = true so it is
  # mounted back in initrd and is present when the users/groups activation reads
  # it (which runs before ordinary stage-2 bind mounts).
  #   one-time on wheatley:  sudo mkdir -p /persist/var/lib/nixos
  fileSystems."/var/lib/nixos" = {
    device = "/persist/var/lib/nixos";
    fsType = "none";
    options = [ "bind" ];
    neededForBoot = true;
  };
  fileSystems."/root" = {
    device = "/persist/root";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/lib/acme" = {
    device = "/persist/var/lib/acme";
    fsType = "none";
    options = [ "bind" ];
  };

  # loginctl-linger -- this enables "lingering" for selected users
  # inspired by the discussion (and linked code) in https://github.com/NixOS/nixpkgs/issues/3702
  # this should just be a NixOS option really
  fileSystems."/var/lib/systemd/linger" = {
    device = "/persist/var/lib/systemd/linger";
    fsType = "none";
    options = [ "bind" ];
  };

  # machine-id is used by systemd for the journal
  # this allows to use journalctl to look at journals for previous boots
  environment.etc."machine-id".source = "/persist/etc/machine-id";

  # kernel modules are exposed at /lib/modules
  fileSystems."/lib/modules" = {
    device = "/run/booted-system/kernel-modules/lib/modules";
    fsType = "none";
    options = [ "bind" ];
  };

}
