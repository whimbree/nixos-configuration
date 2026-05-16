# Shared profiles applied to every physical host via mkHost in flake.nix.
# To apply something everywhere: add it here.
# To override per-host: set the option again in the host config (scalars use
# last-write-wins priority; use lib.mkForce to beat a mkDefault in here).
[
  ./common.nix
  ./ssh.nix
  ./networking-base.nix
  ./users.nix
]
