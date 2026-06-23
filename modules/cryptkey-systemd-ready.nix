# Workaround for nixpkgs dropping
# 0001-Start-device-units-for-uninitialised-encrypted-devic.patch
# (https://github.com/NixOS/nixpkgs/commit/b5611f9).
#
# Our hosts unlock a small LUKS "cryptkey" device with a passphrase in initrd and
# use its decrypted payload as a raw key (keyFile = /dev/mapper/cryptkey) for
# cryptswap and the ZFS pools. That mapping has no filesystem signature, so under
# systemd initrd the stock 99-systemd.rules marks it SYSTEMD_READY=0 and
# dev-mapper-<name>.device never activates, stalling everything that depends on it.
#
# This forces the key devices ready. The zz- filename prefix sorts the rule after
# 99-systemd.rules so the assignment wins. Key device names are derived from any
# LUKS device whose keyFile points at /dev/mapper/<name>, i.e. another mapping.
#
# Only relevant under systemd initrd; a no-op on scripted-initrd hosts.
#
# TODO: drop this per-host once that host's cryptkey is repartitioned with a real
# filesystem and the key is read from a file inside it rather than raw bytes at
# offset 0 (an FS signature makes systemd mark the device ready on its own).
{ config, lib, pkgs, ... }:
let
  keyDeviceNames = lib.pipe config.boot.initrd.luks.devices [
    lib.attrValues
    (builtins.filter
      (d: d.keyFile != null && lib.hasPrefix "/dev/mapper/" d.keyFile))
    (map (d: lib.removePrefix "/dev/mapper/" d.keyFile))
    lib.unique
  ];

  keyDeviceUdevRules =
    pkgs.writeTextDir "etc/udev/rules.d/zz-cryptsetup-key-devices-ready.rules"
    (lib.concatMapStringsSep "\n" (name:
      ''SUBSYSTEM=="block", KERNEL=="dm-*", ENV{DM_NAME}=="${name}", ENV{DM_UUID}=="CRYPT-*", ENV{SYSTEMD_READY}="1"'')
      keyDeviceNames);
in
lib.mkIf (config.boot.initrd.systemd.enable && keyDeviceNames != [ ]) {
  boot.initrd.services.udev.packages = [ keyDeviceUdevRules ];
}
