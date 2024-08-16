{ config, pkgs, ... }:
# https://github.com/openzfs/zfs/issues/15140
# https://github.com/whimbree/zfs/blob/fix_15140_patch/patches/fix_15140.patch
let zfsVersionSuffix = "-fix_15140";
in {
  nixpkgs.overlays = [
    (final: prev: {
      zfs = prev.zfs.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          (final.fetchpatch {
            name = "fix_15140.patch";
            url =
              "https://raw.githubusercontent.com/whimbree/zfs/fix_15140_patch/patches/fix_15140.patch";
            sha256 = "sha256-w2nGg/2JIaWJ+ge7ozRAtfCwqpmwEfStgpreQ5o00mI=";
          })
        ];
        postPatch = (oldAttrs.postPatch or "") + ''
          # Get the current version
          current_version=$(grep 'Version:' META | awk '{print $2}')

          # Set the new version
          new_version="$current_version${zfsVersionSuffix}"

          # Update the META file
          sed -i 's/^Version: .*/Version: '"$new_version"'/' META
        '';
      });
    })
  ];

  boot.zfs.package = pkgs.zfs;
}
