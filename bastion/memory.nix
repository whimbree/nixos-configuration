{ ... }: {
  swapDevices =
    [{ device = "/dev/disk/by-uuid/47644549-bfbf-41b1-8fd7-900d3c10480e"; }];

  boot.kernelParams = [
    # zswap: compressed swap cache in RAM (zstd + zsmalloc).
    # 35% pool cap — VMs generate heavy swap; more compressed cache reduces disk I/O.
    "zswap.enabled=1"
    "zswap.max_pool_percent=35"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
  ];

  boot.kernel.sysctl = {
    # Prefer cache reclaim over swap. 1 (not 0) still allows swap as last resort.
    "vm.swappiness" = 1;

    # Mostly inert on this host — slab is ZFS ARC, not VFS dentry/inode.
    # Covers non-ZFS paths (ext4, tmpfs, virtiofs). Default: 100.
    "vm.vfs_cache_pressure" = 200;

    # Reserves 512 MB free and sets the min watermark that low/high derive from.
    # Too high starves working set and triggers false direct reclaim; too low and
    # kswapd can't service atomic allocations under pressure.
    "vm.min_free_kbytes" = 524288;

    # Widens kswapd's low→high watermark gap to 0.5% of RAM (~300 MB on 62 GB).
    # Default 0.1% (~60 MB) is too narrow — kswapd thrashes on/off. Units: 1/10000.
    "vm.watermark_scale_factor" = 50;

    # Marginal on a ZFS host since ZFS bypasses page cache for writes.
    # Low values limit dirty page pileup on non-ZFS paths (ext4, tmpfs)
    # during pressure spikes. Defaults (10/20) are for systems where Linux
    # page cache IS the write path and batching improves throughput.
    "vm.dirty_background_ratio" = 1;
    "vm.dirty_ratio" = 5;
  };
}
