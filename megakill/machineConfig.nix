# Hardware-specific identifiers for megakill.
# When migrating to new hardware, this is the only file that needs updating.
# Passed into all modules via specialArgs as `machineConfig`.
{
  hostId = "0efa0ed8"; # ZFS requires a unique 8-hex-digit host identifier

  luks = {
    cryptkeyUuid  = "cc34a9f2-34e4-4a6a-b044-16621f5c988a"; # key device
    cryptswapUuid = "500a8f51-2f5a-4ba7-9b25-0b3b75570b76"; # swap device
  };

  swap = {
    uuid = "ce7cc84f-3d43-45d7-ac1b-79ec897d54ab";
  };

  gpu = {
    # Nvidia RTX 3090 (secondary — host driver by default, VFIO for passthrough)
    nvidia = {
      name       = "RTX 3090";
      pciId      = "10de:2204"; # Graphics
      audioPciId = "10de:1aef"; # Audio (HDMI, same IOMMU group)
      vfioGroup  = "30";        # /dev/vfio/30 — IOMMU group on this motherboard
    };
  };
}
