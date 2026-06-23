{ ... }: {
  swapDevices =
    [{ device = "/dev/disk/by-uuid/6a2d4879-5288-4350-b1c4-68f01fd03507"; }];

  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.max_pool_percent=25"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
  ];

  boot.kernel.sysctl."vm.swappiness" = 1;
  boot.kernel.sysctl."vm.vfs_cache_pressure" = 50;
  # https://askubuntu.com/questions/41778/computer-freezing-on-almost-full-ram-possibly-disk-cache-problem/922946#922946
  boot.kernel.sysctl."vm.min_free_kbytes" = 65536;
}
