# Megakill Phase 1 — Migrate megakill-old functionality into megakill

## Goal
Bring the new `megakill/` config up to feature parity with `megakill-old/`,
replacing Docker with Podman, organizing into focused files, and commenting
non-obvious config.

## Status
- [x] ZFS + impermanence (`zfs.nix`, `persist.nix`)
- [x] Tailscale (`tailscale.nix`)
- [x] zswap via kernel params (in `hardware-configuration.nix`)
- [x] `boot.zfs.forceImportRoot = true` (explicit, with comment)
- [x] Add impermanence input to `flake.nix`
- [x] `networking.nix`
- [x] `audio.nix`
- [x] `gpu.nix`
- [x] `virtualisation.nix`
- [x] `nas.nix` (written; import commented out until Tailscale is connected)
- [x] `backup.nix` (written; import commented out until Tailscale is connected)
- [x] `configuration.nix` additions
- [x] Copy `modules/` from megakill-old

---

## Files to create

### `megakill/networking.nix`
- DNS-over-TLS via `systemd-resolved` (Cloudflare 1.1.1.1 / 1.0.0.1, DNSSEC, `~.` domain catch-all)
- `networking.useNetworkd = true`
- Disable `systemd.network.wait-online` and `NetworkManager-wait-online`
  (both cause slow boots on a desktop and are redundant with NetworkManager)

### `megakill/audio.nix`
- `services.pulseaudio.enable = false`
- `security.rtkit.enable = true` (needed for pipewire real-time priority)
- `services.pipewire` with alsa (+ 32bit), pulse compat, jack
- Low-latency pipewire config: 32-sample quantum at 48 kHz
- WirePlumber bluetooth codec config: SBC-XQ, mSBC, HFP/HSP headset roles

### `megakill/gpu.nix`
- `boot.initrd.kernelModules = [ "amdgpu" ]`
  (must be in initrd or display disappears when Nvidia card is bound to VFIO)
- `hardware.graphics` with ROCm OpenCL packages
- `hardware.nvidia`: secondary card, modesetting disabled
  (two GPUs with modesetting both on breaks display), stable driver

### `megakill/virtualisation.nix`
- libvirtd: `qemu_kvm`, `virtiofsd`, `swtpm` (TPM emulation for Windows),
  `runAsRoot = false`, device ACL for kvmfr + vfio
- kvmfr: Looking Glass shared memory device (512 MB, kvm group)
- VFIO specialisation: AMD IOMMU, RTX 3090 (10de:2204 / 10de:1aef),
  blacklist Nvidia, ignore MSRs, disable PCIe ASPM
- Podman (NOT Docker — Docker is banned)
- spice USB redirection
- virt-manager + dconf
- Imports `./modules/vfio.nix`, `./modules/kvmfr-options.nix`

### `megakill/nas.nix`
- NFS automounts (x-systemd.automount, noauto, 30-min idle timeout):
  - `/home/bree/nas` → `bastion:/export/nas/bree`
  - `/mnt/images` → `bastion:/export/images`
- CIFS automounts (same automount pattern, credentials from `~/.smbcredentials`):
  - `/mnt/media`, `/mnt/downloads`, `/mnt/public` → `//bastion/*`
  - `noperm` so file ownership doesn't fight with the local user

### `megakill/backup.nix`
- `services.zfs.autoScrub` monthly on `rpool` and `lake`
- `services.znapzend`:
  - `rpool/safe/home`: hourly snaps, keep 1 day; daily, keep 1 month; monthly, keep 1 year
    → replicate to `ocean/backup/megakill/rpool/safe/home` on bastion
  - `rpool/safe/persist`: same schedule + replication
  - `lake/data`: snapshot only, no remote (too large to replicate)
- Note: znapzend SSH uses `root@bastion`. Bastion already has megakill's root
  SSH key in `bree`'s authorized_keys. Ensure `/persist/root/.ssh/` has the
  matching private key.

### `megakill/modules/` (copy from megakill-old, no changes)
- `vfio.nix` — NixOS module for AMD/Intel IOMMU + vfio-pci binding
- `kvmfr-options.nix` — NixOS module declaring `virtualisation.kvmfr` options
- `kvmfr-package.nix` — kvmfr kernel module package
- `apple_fonts.nix` — Apple SF Pro font package (fetched from Apple CDN)

---

## `configuration.nix` additions

### Locale / time
```nix
time.timeZone = "America/New_York";
i18n.defaultLocale = "en_US.UTF-8";
i18n.extraLocaleSettings = { LC_* = "en_US.UTF-8"; ... };
services.xserver.xkb = { layout = "us"; variant = ""; };
```

### Programs
```nix
programs.kdeconnect.enable = true;
programs.direnv.enable = true;
programs.mtr.enable = true;
programs.gnupg.agent = { enable = true; enableSSHSupport = true; pinentryPackage = pkgs.pinentry-qt; };
```

### Services
```nix
services.printing = { enable = true; drivers = [ pkgs.hplip ]; };
services.pcscd.enable = true;   # Yubikey smartcard / CCID mode
services.sysstat.enable = true;
services.openssh = { ... };     # key-only, no root login, VERBOSE
```

### System
```nix
systemd.settings.Manager.DefaultTimeoutStopSec = "30s";
boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];
boot.kernelModules = [ "zenpower" ];   # AMD CPU power monitoring
```

### Fonts
- Apple SF Pro (via `modules/apple_fonts.nix`)
- Fira Code, Source Code Pro, Source Sans Pro, Source Serif Pro
- fontconfig defaults: monospace = Fira Code, sans/serif = SF Pro Display

### Git safe.directory (from bastion)
```nix
environment.etc."gitconfig".text = ''
  [safe]
    directory = /etc/nixos
'';
```
Needed because /etc/nixos is owned by bree but nixos-rebuild runs git as root.

### Packages to add
- `bisq2`, `wasabiwallet` (Bitcoin clients)
- Qt/KDE: `qtstyleplugin-kvantum`, `kimageformats`, `qt6.qtimageformats`

### Packages to confirm present (already in current configuration.nix)
- `looking-glass-client`, `virtiofsd`, `virt-manager` (add)

---

## Import order in `configuration.nix`
```nix
imports = [
  ./hardware-configuration.nix
  ./zfs.nix
  ./persist.nix
  ./tailscale.nix
  ./networking.nix
  ./audio.nix
  ./gpu.nix
  ./virtualisation.nix
  ./nas.nix
  ./backup.nix
];
```

---

## Things deliberately NOT ported from megakill-old
- Docker (banned — use Podman)
- Minecraft servers / watchtower / socks proxy (`services.nix`) — situational
- `boot.initrd.network.ssh` (initrd SSH for remote LUKS unlock) — was in old
  `boot.nix`, not needed now that LUKS is handled differently. Re-add if wanted.
- Old `boot.nix` ZFS udev scheduler rule — re-evaluate if needed
