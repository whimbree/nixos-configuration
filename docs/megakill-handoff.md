# megakill — Agent Handoff

## Current State (as of 2026-05-13)

The system boots cleanly with systemd stage 1 initrd. The big-picture plan for
megakill is documented in `docs/megakill_restructure_7889bac0.plan.md`.

---

## What Was Done This Session

### 1. Fresh install boot loop fixed

The original problem was an infinite "Started D-Bus System Message Bus" loop.
Root cause: `boot.initrd.systemd.enable` was implicitly true somewhere in the
new config, but the LUKS/ZFS hooks were still using the old scripted-initrd
API (`postMountCommands`, `postResumeCommands`), which is not supported with
systemd stage 1. NixOS throws a hard assertion failure for this mismatch.

Fix: added `boot.initrd.systemd.enable = false` to `megakill/zfs.nix` as a
temporary workaround so the system could boot. This was then properly resolved
in the next step.

### 2. Migrated to systemd stage 1 initrd (commit `cab74c6`)

NixOS is deprecating scripted initrd hooks in 26.11. The two hooks were
migrated to proper `boot.initrd.systemd.services` entries in
`megakill/zfs.nix`:

- **close-cryptkey** — closes `/dev/mapper/cryptkey` after it has been used as
  a keyfile to unlock `cryptswap`. The keyfile device must not remain mapped at
  runtime.
- **rollback** — runs `zfs rollback -r rpool/local/root@blank` before
  `sysroot.mount`, implementing the ephemeral root pattern.

### 3. Fixed close-cryptkey race + fault tolerance (commit `d7adf76`)

First boot after migration showed `[FAILED] Failed to start Close cryptkey LUKS device`.

Two bugs:
- **Race condition**: was ordered `after = [ "cryptsetup.target" ]`, but
  `cryptsetup.target` activates before all its wanted units complete. cryptswap
  could still be reading from cryptkey when close-cryptkey fired.
  Fix: `after = [ "systemd-cryptsetup@cryptswap.service" ]` — wait for the
  last consumer of cryptkey specifically.
- **Hard failure on absent device**: if cryptkey is already gone, `cryptsetup
  close` exits non-zero and systemd marks the service failed.
  Fix: `ExecStart = "-${pkgs.cryptsetup}/bin/cryptsetup close ..."` — the `-`
  prefix is the standard systemd idiom for "tolerate non-zero exit".

Second boot succeeded. System is online.

---

## Outstanding Issue

`/dev/mapper/cryptkey` is **still present after login** in the running system.

This means `close-cryptkey` is either:
1. Not being activated at all (not pulled into the initrd boot graph)
2. Running but failing silently (the `-` prefix hides the error)
3. Succeeding in initrd but the device reappears in stage 2 (unlikely but
   possible if something in stage 2 re-opens it)

### Suggested debugging steps

On the running system:

```sh
# Check if the service ran and what it did
journalctl -b | grep -i 'close-cryptkey\|cryptkey'

# Check the device
ls -la /dev/mapper/cryptkey
dmsetup info cryptkey

# Check if it was opened by something in stage 2
systemctl status systemd-cryptsetup@cryptkey.service 2>/dev/null
```

### Likely fix

The `wantedBy = [ "cryptsetup.target" ]` in `close-cryptkey` places this unit
in **initrd**. If `cryptsetup.target` in the initrd is not pulling it in
(because it has no `Requires=` for it, only `Wants=` which is non-fatal if the
service isn't present), then the service simply doesn't run.

A more robust approach used in the community is to order after the specific
cryptsetup service AND add a `requires` or `bindsTo` to force activation:

```nix
boot.initrd.systemd.services.close-cryptkey = {
  wantedBy = [ "cryptsetup.target" ];
  after = [ "systemd-cryptsetup@cryptswap.service" ];
  requires = [ "systemd-cryptsetup@cryptswap.service" ];
  before = [ "sysroot.mount" ];
  unitConfig.DefaultDependencies = false;
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "-${pkgs.cryptsetup}/bin/cryptsetup close /dev/mapper/cryptkey";
  };
};
```

Alternatively, if stage 2 is re-opening it: check whether
`boot.initrd.luks.devices.cryptkey` generates a `systemd-cryptsetup@cryptkey`
unit that persists into stage 2.

---

## Next Steps (from the restructure plan)

The plan lives at `docs/megakill_restructure_7889bac0.plan.md`. The systemd
initrd migration is now done. The next steps in order are:

1. **Fix `/dev/mapper/cryptkey` still being present** (immediate)
2. Add `disko` and `impermanence` as flake inputs in `flake.nix`
3. Create `megakill/disko.nix`
4. Rewrite `megakill/persist.nix` using `environment.persistence`
5. Create topic modules: `networking.nix`, `users.nix`, `nix.nix`,
   `desktop.nix`, `audio.nix`, `packages.nix`
6. Port from `megakill-old/`: `tailscale.nix`, `gpu.nix`, `virtualisation.nix`,
   `bastion-nas.nix`, `backup.nix`, `services.nix`
7. Slim `configuration.nix` to an index-only file

Each step should be one `nixos-rebuild boot` + reboot before moving to the next.

---

## Key Files

| File | Purpose |
|------|---------|
| `megakill/configuration.nix` | Current entry point, still monolithic |
| `megakill/zfs.nix` | Boot, LUKS, ZFS, initrd services — the file actively being worked on |
| `megakill/persist.nix` | Minimal bind mount for `/etc/nixos` only |
| `megakill/hardware-configuration.nix` | Generated, no fileSystems for lake yet |
| `megakill-old/` | Full previous config — reference for porting modules back |
| `docs/megakill_restructure_7889bac0.plan.md` | Full restructure plan with rationale |
| `flake.nix` | `megakill` host entry — needs `disko` and `impermanence` inputs added |

## Disk Layout (megakill)

- `/dev/nvme0n1` — NVMe SSD
  - p1: `/boot/efi` (vfat)
  - p2: `/boot` (vfat)
  - LUKS `cryptkey` (UUID `cc34a9f2-...`) — keyfile device for cryptswap
  - LUKS `cryptswap` (UUID `500a8f51-...`) — encrypted swap, keyfile=cryptkey, keyFileSize=64
  - ZFS `rpool` — native ZFS encryption, datasets: `local/root` (ephemeral, rolls back to `@blank`), `local/nix`, `safe/home`, `safe/persist`
- `lake` — 20TB ZFS mirror (separate drives), dataset `lake/data`
