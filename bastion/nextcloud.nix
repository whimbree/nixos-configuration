{ config, pkgs, ... }: 
  let
    unstable = import
    (builtins.fetchTarball https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz)
    # reuse the current configuration
    { config = config.nixpkgs.config; };
  in {

  networking.firewall.allowedTCPPorts = [ 80 ];

  services.nextcloud = {
    package = unstable.nextcloud25;
    enable = true;
    hostName = "nextcloud.bspwr.com";

    # Use HTTPS for links
    https = true;

    # Auto-update Nextcloud Apps
    autoUpdateApps.enable = true;
    # Set what time makes sense for you
    autoUpdateApps.startAt = "05:00:00";

    config = {
      # Further forces Nextcloud to use HTTPS
      overwriteProtocol = "https";

      # Nextcloud PostegreSQL database configuration, recommended over using SQLite
      dbtype = "pgsql";
      dbuser = "nextcloud";
      dbhost = "/run/postgresql"; # nextcloud will add /.s.PGSQL.5432 by itself
      dbname = "nextcloud";
      dbpassFile = "/persist/var/nextcloud-db-pass";

      adminpassFile = "/persist/var/nextcloud-admin-pass";
      adminuser = "admin";
    };
  };

  # use PostgreSQL with Nextcloud
  services.postgresql = {
    enable = true;

    # Ensure the database, user, and permissions always exist
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [{
      name = "nextcloud";
      ensurePermissions."DATABASE nextcloud" = "ALL PRIVILEGES";
    }];
  };

  # ensure PostgreSQL is running before Nextcloud
  systemd.services."nextcloud-setup" = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };
}