# Single source of truth for all VMs
{
  # Defaults are merged into every registered VM before derived fields such as
  # hostname, IP, MAC, and interface ID are calculated. Individual VMs may
  # override these values (for example, `observability = false`).
  defaults = {
    hypervisor = "bastion";
    observability = true;
  };

  vms = {
    # Tier 0 - Infrastructure/DMZ
    gateway = {
      tier = 0;
      index = 1;
      autostart = true;
      sops = true; # derive an age key image; secrets/bastion/gateway.yaml
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

    blog = {
      tier = 1;
      index = 3;
      autostart = true;
      description = "Blog";
    };

    airvpn-switzerland = {
      tier = 1;
      index = 4;
      autostart = true;
      description = "Airvpn Switzerland + Tailscale";
    };

    webrtc = {
      tier = 1;
      index = 5;
      autostart = true;
      sops = true; # derive an age key image; secrets/bastion/webrtc.yaml
      description = "WebRTC services (coturn, LiveKit)";
    };

    liquidagent = {
      tier = 1;
      index = 6;
      autostart = true;
      sops = true; # derive an age key image; secrets/bastion/liquidagent.yaml (initial login password)
      description = "Liquid: self-hosted AI agent + software factory";
    };

    forgejo-runner = {
      tier = 1;
      index = 7;
      autostart = true;
      sops = true; # derive an age key image; secrets/bastion/forgejo-runner.yaml (runner registration token)
      description = "Forgejo Actions runner (untrusted CI workloads)";
    };

    jellyfin = {
      tier = 2;
      index = 1;
      autostart = true;
      description = "Jellyfin 10.11.x";
    };

    filebrowser = {
      tier = 2;
      index = 2;
      autostart = true;
      description = "Filebrowser";
    };

    navidrome = {
      tier = 2;
      index = 4;
      autostart = true;
      description = "Navidrome music server";
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

    # syncthing = {
    #   tier = 3;
    #   index = 4;
    #   autostart = true;
    #   description = "Syncthing file synchronization";
    # };

    sftpgo = {
      tier = 3;
      index = 5;
      autostart = true;
      description = "SFTPGo";
    };

    webdav = {
      tier = 3;
      index = 6;
      autostart = true;
      description = "Webdav for Duplicati backups";
    };

    fluxer = {
      tier = 3;
      index = 7;
      autostart = true;
      sops = true; # derive an age key image; secrets/bastion/fluxer.yaml
      description = "Fluxer chat server";
    };

    forgejo = {
      tier = 3;
      index = 8;
      autostart = true;
      description = "Forgejo git forge";
    };

    observability = {
      tier = 3;
      index = 9;
      autostart = true;
      sops = true; # derived age key; secrets/bastion/observability.yaml
      description = "ClickStack observability platform";
    };

  };
}
