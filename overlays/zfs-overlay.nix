{ config, pkgs, ... }: {
  nixpkgs.overlays = [
    (final: prev: {
      zfs = prev.zfs.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          (final.fetchpatch {
            name = "fix_15140.patch";
            url = "https://raw.githubusercontent.com/whimbree/zfs/fix_15140_patch/patches/fix_15140.patch";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          })
        ];
      });
    })
  ];
}
