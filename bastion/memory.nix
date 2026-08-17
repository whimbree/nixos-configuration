{ ... }: {
  swapDevices =
    [{ device = "/dev/disk/by-uuid/47644549-bfbf-41b1-8fd7-900d3c10480e"; }];

  boot.kernelParams = [
    # zswap: compressed swap cache in RAM (zstd + zsmalloc).
    # Retain the effective 35% ceiling for VM-heavy workloads. The shrinker
    # lets the kernel write cold compressed pages to the backing NVMe swap when
    # active workloads need that memory, without prematurely constraining the
    # useful compressed cache.
    "zswap.enabled=1"
    "zswap.max_pool_percent=35"
    "zswap.shrinker_enabled=1"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
  ];

  boot.kernel.sysctl = {
    # Use zswap conservatively before the host is forced into synchronous
    # reclaim. The previous value of 1 left 40 GiB of swap effectively idle
    # during the build-induced memory-pressure event.
    "vm.swappiness" = 20;

    # Use the balanced kernel default. A value of 200 doubles the preference
    # for dentry/inode reclaim and adds lock work in shrink_slab, where the
    # failed build's kernel trace was already stalled.
    "vm.vfs_cache_pressure" = 100;

    # Reserves 512 MB free and sets the min watermark that low/high derive from.
    # Too high starves working set and triggers false direct reclaim; too low and
    # kswapd can't service atomic allocations under pressure.
    "vm.min_free_kbytes" = 524288;

    # Keep kswapd ahead of short VM/build allocation bursts. A 1% watermark
    # distance gives background reclaim more time before allocating tasks must
    # enter direct reclaim. Default: 10 (0.1%); units are 1/10000 of RAM.
    "vm.watermark_scale_factor" = 100;

    # Marginal on a ZFS host since ZFS bypasses page cache for writes.
    # Low values limit dirty page pileup on non-ZFS paths (ext4, tmpfs)
    # during pressure spikes. Defaults (10/20) are for systems where Linux
    # page cache IS the write path and batching improves throughput.
    "vm.dirty_background_ratio" = 1;
    "vm.dirty_ratio" = 5;
  };
}
