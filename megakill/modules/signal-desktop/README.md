# signal-desktop (vendored)

This directory is a **vendored copy** of the `signal-desktop` package from
nixpkgs. The 8.23.0 bump is based on the nixpkgs 8.21.0 package at:

<https://github.com/NixOS/nixpkgs/tree/01e6b20722599fa01219db9744ee732a72ff548d/pkgs/by-name/si/signal-desktop>

We vendor it so we can run a newer release than nixpkgs currently ships. It is
built and wired into `megakill` via a `nixpkgs.overlays` entry in
[`../../configuration.nix`](../../configuration.nix) that overrides the
top-level `signal-desktop` attribute:

```nix
nixpkgs.overlays = [
  (final: prev: {
    signal-desktop = final.callPackage ./modules/signal-desktop/package.nix { };
  })
];
```

## Current pin

**Signal Desktop 8.23.0.** nixpkgs master is still on 8.21.0
(`01e6b207`) at the time of this bump. Native dependency versions come from
upstream `package.json`:

| File                  | 8.18.0-beta.1 | 8.23.0     |
| --------------------- | ------------- | ---------- |
| `libsignal-node.nix`  | 0.96.3        | **0.99.2** |
| `signal-sqlcipher.nix`| 3.3.9         | **4.0.3**  |
| `ringrtc.nix`         | 2.69.4        | **2.70.2** |
| `webrtc-sources.json` | 7778c         | **7871e**  |

`ringrtc` 2.70.2 pins WebRTC `7871e` (nixpkgs 8.21.0 used `7871d`). That is a
Chromium bump, so `webrtc.nix` follows current nixpkgs (LLVM 22 patches
including `chromium-149-llvm-22.patch`).

`node-sqlcipher` 4.x pins `pnpm@11`, so both the top-level package and
`signal-sqlcipher` now use `pnpm_11`.

## Build notes (not handled by `update.sh`)

1. **pnpm 11.** Workspace config (including `patchedDependencies`) lives in
   `pnpm-workspace.yaml`. The top-level install uses `pnpm_11`.
2. **`verifyDepsBeforeRun`.** Upstream sets `verifyDepsBeforeRun: prompt`, which
   aborts in the non-interactive Nix sandbox. `postPatch` rewrites it to
   `false` (deps are already installed frozen/offline by `pnpmConfigHook`).
3. **sticker/art creator built inline.** It is a member of the root pnpm
   workspace (`signal-art-creator`). `preBuild` runs
   `pnpm --filter signal-art-creator run build`; electron-builder bundles
   `sticker-creator/dist`.
4. **`@signalapp/windows-ucv` and `@signalapp/types`.** Their prepare/preinstall
   scripts do not run under `pnpmConfigHook` (`--ignore-scripts`), so `preBuild`
   transpiles both. The Windows native addon is only loaded on win32.
5. **`replace-apple-emoji-with-noto-emoji.patch`.** Replaces the unlicensed Apple
   emoji font with Noto Color Emoji.
6. **`dont-assert-unicode-17-emoji.patch`.** Drops an `isEmoji` assert that fails
   when Node's `emoji-regex-xs` lags Unicode 17.

## Updating

`update.sh` is the upstream nixpkgs auto-updater. It assumes a nixpkgs
`default.nix` layout and a `sticker-creator` subpackage, so it fails in this
vendored tree (`path '.../default.nix' does not exist`). Bump versions and
hashes by hand.

To recompute a fixed-output hash, set it to
`sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` and build the relevant
sub-derivation; Nix prints the correct hash. For example:

```sh
nix build .#nixosConfigurations.megakill.pkgs.signal-desktop.pnpmDeps
nix build .#nixosConfigurations.megakill.pkgs.signal-desktop.libsignal-node.cargoDeps
```

New files (patches, etc.) must be `git add`'d before a flake build, or Nix will
not see them.
