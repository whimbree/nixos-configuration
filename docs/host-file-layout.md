# Host file layout

Convention for how each physical host's NixOS config is split into files. Hosts
covered: `megakill`, `bastion`, `wheatley`. The goal is that the same concern
lives under the same filename on every host, so "where do I find X?" has one
answer.

## Canonical files

Each host's `configuration.nix` imports a set of single-concern files. The
shared, canonical names are:

| File | Owns |
| --- | --- |
| `configuration.nix` | Entrypoint: the `imports` list, host identity (`networking.hostName`), user accounts, `environment.systemPackages`, `system.autoUpgrade`, `system.stateVersion`. |
| `hardware-configuration.nix` | Generated `nixos-generate-config` scan only: detected kernel modules, the `fileSystems` mount table, `hostPlatform`, microcode. Treat as regenerable. |
| `boot.nix` | Bootloader, initrd, `boot.initrd.systemd.enable`, LUKS devices + unlock plumbing (including remote-unlock over SSH), `close-cryptkey`, and hardware-level kernel params (e.g. nvme/pcie workarounds, `ip=dhcp`). |
| `zfs.nix` | ZFS: pools, `networking.hostId`, `boot.supportedFilesystems`, ARC/scheduler kernel params, `boot.zfs.*`, scrub/snapshot policy (`autoScrub`, `znapzend`), `zfs-import-*` ordering, and the ephemeral-root `rollback`. |
| `memory.nix` | `swapDevices`, zswap kernel params, and `vm.*` sysctls (swappiness, cache pressure, watermarks, dirty ratios). |
| `persist.nix` | Impermanence / persisted paths for the ephemeral root. |
| `networking.nix` | Host networking. |
| `tailscale.nix` | Tailscale / headscale client config. |

As-applicable (only on hosts that have the concern), still using a fixed name:
`nas.nix`, `backup.nix`, `services.nix`, `sops.nix`, `virtualisation.nix`.

## Conventions

- Spelling: use British `virtualisation.nix`, matching the NixOS option
  namespace `virtualisation.*`.
- `kernelParams` are split by concern across files (each file may contribute to
  the merged `boot.kernelParams` list): hardware/boot params in `boot.nix`, ZFS
  ARC/scheduler params in `zfs.nix`, zswap in `memory.nix`.
- initrd units are grouped with the subsystem whose tooling they drive:
  - `close-cryptkey` runs `cryptsetup close` -> `boot.nix`.
  - `rollback` and `zfs-import-*` run/order ZFS -> `zfs.nix`.
  Cross-file `after`/`requires` references between these units are fine; systemd
  resolves them by unit name regardless of which file defines them.
- The mount table stays in `hardware-configuration.nix` where that generated
  file exists (megakill, wheatley).

## Known deviations

- `bastion` has no generated `hardware-configuration.nix`. Its mount table lives
  in a dedicated `filesystem.nix` (mounts + mergerfs), and it imports
  `not-detected.nix` directly from `configuration.nix`.
- `bastion` is still on scripted initrd (`boot.initrd.systemd.enable = false`);
  its `boot.nix` therefore uses scripted hooks (`preLVMCommands`,
  `postMountCommands`) rather than systemd initrd services. megakill and wheatley
  use systemd stage-1 initrd.
- `bastion` does not use `sops` itself yet (only its MicroVMs do, via
  `modules/sops-vm-keys.nix`), so it has no `sops.nix`.
