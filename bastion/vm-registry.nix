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
    
  };
}
