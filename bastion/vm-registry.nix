# Single source of truth for all VMs
{
  vms = {
    # Tier 0 - Infrastructure/DMZ
    gateway = {
      tier = 0;
      index = 1;
      autostart = false;
      description = "Reverse proxy for external access";
    };

    airvpn-sweden = {
      tier = 1;
      index = 1;
      autostart = true;
      description = "Airvpn Sweden + Tailscale";
    };

    airvpn-usa = {
      tier = 1;
      index = 2;
      autostart = true;
      description = "Airvpn USA + Tailscale";
    };

    jellyfin = {
      tier = 2;
      index = 1;
      autostart = true;
      description = "Jellyfin";
    };

    immich = {
      tier = 3;
      index = 1;
      autostart = true;
      description = "Immich";
    };

    nextcloud = {
      tier = 3;
      index = 2;
      autostart = true;
      description = "Nextcloud";
    };

    photoprism = {
      tier = 3;
      index = 3;
      autostart = true;
      description = "PhotoPrism photo viewer";
    };

    syncthing = {
      tier = 3;
      index = 4;
      autostart = true;
      description = "Syncthing file synchronization";
    };

  };
}
