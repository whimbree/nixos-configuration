# signal-desktop (vendored)

This directory is a **vendored copy** of the `signal-desktop` package from
nixpkgs, taken from:

<https://github.com/NixOS/nixpkgs/tree/0c3200c80e1c7604af593a82d6d9a9272f071024/pkgs/by-name/si/signal-desktop>

At that commit the nixpkgs package built **Signal Desktop 8.15.0**. We vendor it
so we can run a newer release than nixpkgs currently ships. It is built and wired
into `megakill` via a `nixpkgs.overlays` entry in
[`../../configuration.nix`](../../configuration.nix) that overrides the
top-level `signal-desktop` attribute:

```nix
nixpkgs.overlays = [
  (final: prev: {
    signal-desktop = final.callPackage ./modules/signal-desktop/package.nix { };
  })
];
```

## What we changed vs. upstream

Bumped from **8.15.0 → 8.18.0-beta.1**. Signal only tags minor releases
(`8.15.0`, `8.16.0`, `8.17.0`, `8.18.0-beta.1`, ...); there is no `8.17.3`.

### Version + hashes (`package.nix`)

- `version` → `8.18.0-beta.1`, new `src` and `pnpmDeps` hashes.
- `SOURCE_DATE_EPOCH` → the beta's GitHub release timestamp.
- `apple-emoji` hash is unchanged (Signal reuses the same emoji font).

### Vendored native dependencies

The pinned versions must match the upstream `package.json` of the release:

| File                  | 8.15.0  | 8.18.0-beta.1 |
| --------------------- | ------- | ------------- |
| `libsignal-node.nix`  | 0.95.0  | **0.96.3**    |
| `signal-sqlcipher.nix`| 3.3.5   | **3.3.9**     |
| `ringrtc.nix`         | 2.69.3  | **2.69.4**    |
| `webrtc-sources.json` | 7778c   | 7778c (same)  |

`ringrtc` 2.69.4 pins the same WebRTC revision (`7778c`) as 2.69.3, so
`webrtc-sources.json` / `webrtc.nix` are untouched and the (very expensive)
Chromium/WebRTC build is reused from the binary cache.

### Beta-specific build fixes (not handled by `update.sh`)

These are the manual changes required beyond a plain version/hash bump, because
Signal restructured its build between 8.15 and 8.18:

1. **pnpm 11.** 8.18 uses `pnpm@11`, which moved workspace config (including
   `patchedDependencies`) out of `package.json` and into `pnpm-workspace.yaml`.
   The top-level install now uses `pnpm_11`; `signal-sqlcipher` still pins
   `pnpm_10` because `node-sqlcipher` requires it.
2. **`verifyDepsBeforeRun`.** The beta's `pnpm-workspace.yaml` sets
   `verifyDepsBeforeRun: prompt`, which aborts script execution in the
   non-interactive Nix sandbox. `postPatch` rewrites it to `false` (deps are
   already installed frozen/offline by `pnpmConfigHook`).
3. **sticker/art creator built inline.** It became a member of the root pnpm
   workspace (`signal-art-creator`) and its standalone `pnpm-lock.yaml` is now
   stale, so the old separate `sticker-creator` derivation no longer builds.
   We removed it and instead run `pnpm --filter signal-art-creator run build`
   in `preBuild`; electron-builder bundles the resulting `sticker-creator/dist`.
4. **`@signalapp/windows-ucv` built inline.** 8.18 added this local workspace
   package, imported by the main process. Its `dist/index.js` must exist (its
   `preinstall` build hook does not run in the sandbox), so `preBuild` runs
   `pnpm --filter @signalapp/windows-ucv run build`. The Windows native addon is
   only loaded when `process.platform === "win32"`, so on Linux transpiling the
   TypeScript is sufficient.
5. **`replace-apple-emoji-with-noto-emoji.patch`.** The first hunk was updated
   to match the beta's restructured `app/AssetService.main.ts` (the emoji asset
   entry moved into an `if (!process.mas)` block).

## Updating

`update.sh` is the upstream nixpkgs auto-updater. It bumps the version and the
fixed-output hashes, but it does **not** know about the beta-specific fixes
above (pnpm major, `verifyDepsBeforeRun`, the inline workspace builds, or the
emoji-patch context). Expect to re-check those by hand on future bumps.

To recompute a fixed-output hash, set it to
`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` and build the relevant
sub-derivation; Nix prints the correct hash. For example:

```sh
nix build .#nixosConfigurations.megakill.pkgs.signal-desktop.pnpmDeps
nix build .#nixosConfigurations.megakill.pkgs.signal-desktop.libsignal-node.cargoDeps
```
