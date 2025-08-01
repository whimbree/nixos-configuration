# Single source of truth for all VMs
{
  vms = {
    # Tier 0 - Infrastructure/DMZ
    gateway = {
      tier = 0;
      index = 1;
      autostart = true;
      description = "Reverse proxy for external access";
    };

    deluge = {
      tier = 1;
      index = 1;
      autostart = true;
      description = "Deluge";
    };
    
  };
}