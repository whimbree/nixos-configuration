{ config, pkgs, lib, ... }: {
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.whimsical.cloud";
      listen-http = "127.0.0.1:2586";
      behind-proxy = true;

      # Lock the server down: anonymous users can neither read nor write.
      # Access is granted explicitly via `ntfy user`/`ntfy access` (see below).
      auth-default-access = "deny-all";
    };
  };

  # The upstream module sets DynamicUser=true, which makes systemd keep state in
  # /var/lib/private/ntfy-sh and expose /var/lib/ntfy-sh as a symlink. That
  # collides with bind-mounting /var/lib/ntfy-sh (systemd tries to migrate the
  # "public" dir and fails with "Device or resource busy"). The module already
  # declares a static `ntfy-sh` system user, so just disable DynamicUser; then
  # /var/lib/ntfy-sh is a plain state dir we can bind-mount.
  systemd.services.ntfy-sh.serviceConfig.DynamicUser = lib.mkForce false;

  # ntfy stores its state (user.db, cache, attachments) in /var/lib/ntfy-sh.
  # Root is rolled back to blank on every boot, so bind-mount that onto the
  # persistent, backed-up /services dataset. StateDirectory=ntfy-sh fixes
  # ownership on the mounted dir at start.
  #   one-time on wheatley:  sudo mkdir -p /services/ntfy
  fileSystems."/var/lib/ntfy-sh" = {
    device = "/services/ntfy";
    fsType = "none";
    options = [ "bind" ];
  };

  # One-time bootstrap after the first deploy (run on wheatley as root):
  #
  #   # Account you log into from the GrapheneOS ntfy app (read access):
  #   ntfy user add bree
  #   ntfy access bree monitoring read-only
  #
  #   # Token used by Gatus to publish alerts (write access):
  #   ntfy user add --role=admin gatus
  #   ntfy token add gatus          # prints tk_...
  #
  # Put that token into the sops secret (run on any host with the admin key):
  #   sops secrets/wheatley.yaml    # set gatus__ntfy_token: tk_xxxxxxxx
  # then redeploy wheatley so Gatus picks it up.
}
