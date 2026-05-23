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
      # CUPS printer configurations (hplip drivers, added printers).
      "/var/lib/cups"
      "/var/lib/libvirt"
      # UID/GID allocation db; not strictly needed with mutableUsers = false but silences impermanence warning
      "/var/lib/nixos"
      # SDDM last-logged-in user and display manager state.
      "/var/lib/sddm"
      # Last-run timestamps for Persistent=true timers (scrub, znapzend, etc.)
      "/var/lib/systemd/timers"
      # loginctl enable-linger: keeps user session alive when not logged in
      # (needed for user systemd services, rootless podman auto-start, etc.)
      "/var/lib/systemd/linger"
      "/var/lib/tailscale"
      "/root"
    ];
    files = [
      # systemd host credential key — required by libvirt 12.x to decrypt its
      # secrets-encryption-key. Losing this on reboot breaks libvirtd.
      "/var/lib/systemd/credential.secret"
    ];
  };

  # machine-id must be handled via environment.etc, not impermanence — systemd
  # creates /etc/machine-id before impermanence's bind mount service runs
  environment.etc."machine-id".source = "/persist/etc/machine-id";
}
