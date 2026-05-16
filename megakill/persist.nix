{ config, pkgs, lib, ... }: {

  # kernel modules are exposed at /lib/modules via the Nix store
  fileSystems."/lib/modules" = {
    device = "/run/booted-system/kernel-modules/lib/modules";
    fsType = "none";
    options = [ "bind" ];
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      { directory = "/etc/nixos"; user = "bree"; group = "users"; mode = "0755"; }
      "/etc/NetworkManager"
      "/etc/ssh"
      "/var/db/sudo"
      "/var/lib/bluetooth"
      "/var/lib/clamav"
      "/var/lib/containers"
      "/var/lib/libvirt"
      "/var/lib/machines"
      # UID/GID allocation db; not strictly needed with mutableUsers = false but silences impermanence warning
      "/var/lib/nixos"
      "/var/lib/tailscale"
      "/root"
    ];
    files = [];
  };

  # machine-id must be handled via environment.etc, not impermanence — systemd
  # creates /etc/machine-id before impermanence's bind mount service runs
  environment.etc."machine-id".source = "/persist/etc/machine-id";
}
