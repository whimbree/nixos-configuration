---
name: megakill restructure
overview: Reorganize megakill/ into clean topic-separated modules using disko for declarative disk layout and impermanence for stateful path management, mirroring bastion/'s discipline.
todos:
  - id: flake-inputs
    content: Add disko and impermanence as flake inputs in flake.nix; add their NixOS modules to the megakill host entry
    status: pending
  - id: systemd-initrd-migration
    content: Migrate zfs.nix from postMountCommands/postResumeCommands to boot.initrd.systemd.services; remove boot.initrd.systemd.enable = false
    status: pending
  - id: create-disko-nix
    content: Create megakill/disko.nix declaring nvme0n1 partitions, LUKS containers, rpool ZFS datasets with @blank snapshot hook, and lake pool documentation
    status: pending
  - id: update-hardware-configuration
    content: Strip fileSystems.* entries from hardware-configuration.nix (disko generates them); keep kernel modules and sysctl
    status: pending
  - id: create-persist-nix
    content: Rewrite megakill/persist.nix using environment.persistence."/persist" (impermanence) instead of manual bind mounts
    status: pending
  - id: create-networking-nix
    content: Create megakill/networking.nix with NM, networkd, resolved config
    status: pending
  - id: create-users-nix
    content: Create megakill/users.nix
    status: pending
  - id: create-nix-nix
    content: Create megakill/nix.nix (flakes, gc, autoUpgrade, sandbox)
    status: pending
  - id: create-desktop-nix
    content: Create megakill/desktop.nix (Plasma6, SDDM, printing, BT, kdeconnect)
    status: pending
  - id: create-audio-nix
    content: Create megakill/audio.nix (pipewire + low-latency + wireplumber BT)
    status: pending
  - id: create-packages-nix
    content: Create megakill/packages.nix (systemPackages, fonts, programs)
    status: pending
  - id: move-tailscale
    content: Copy megakill-old/tailscale.nix to megakill/tailscale.nix
    status: pending
  - id: move-gpu
    content: Copy megakill-old/gpu.nix to megakill/gpu.nix
    status: pending
  - id: move-virtualisation
    content: Copy megakill-old/virtualisation.nix + modules/ to megakill/
    status: pending
  - id: move-bastion-nas
    content: Copy megakill-old/bastion-nas.nix to megakill/bastion-nas.nix
    status: pending
  - id: move-backup
    content: Copy megakill-old/backup.nix to megakill/backup.nix
    status: pending
  - id: move-services
    content: Copy megakill-old/services.nix + services/ to megakill/ (commented out initially)
    status: pending
  - id: update-configuration-nix
    content: Slim down megakill/configuration.nix to index-only; add all new modules as commented imports to be enabled one at a time
    status: pending
  - id: create-docs-file
    content: Create docs/megakill-structure.md documenting the target layout, module rationale, and import order
    status: pending
  - id: build-verify
    content: nix build .#megakill and verify no errors
    status: pending
isProject: false
---

# megakill Module Restructure Plan

## Goal

Evolve `megakill/` from its minimal post-install state into a clean, reproducible host configuration using:

- **disko** — declarative disk layout (partitions, LUKS, ZFS pool + datasets), making future reinstalls a single command
- **impermanence** — `environment.persistence` replaces all manual bind mounts in `persist.nix`
- **topic modules** — one file per concern, matching the discipline of [`bastion/configuration.nix`](bastion/configuration.nix)

## Step 0: New Flake Inputs

Two new inputs in [`flake.nix`](flake.nix), and their NixOS modules added to the megakill host entry:

```nix
inputs = {
  disko = {
    url = "github:nix-community/disko/latest";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  impermanence.url = "github:nix-community/impermanence";
};

# in nixosConfigurations."megakill"
modules = [
  disko.nixosModules.disko
  impermanence.nixosModules.impermanence
  ./modules/lix.nix
  ./megakill/configuration.nix
];
```

## Proposed File Layout

```
megakill/
  configuration.nix         # index only: imports + hostname + stateVersion
  hardware-configuration.nix # stripped: kernel modules + sysctl only (no fileSystems)
  disko.nix                 # NEW: full disk layout — partitions, LUKS, rpool datasets
  zfs.nix                   # boot + LUKS initrd hooks + kernel params (keep, add lake)
  persist.nix               # REWRITTEN: environment.persistence via impermanence
  networking.nix            # NEW: NM, networkd, resolved, DNS-over-TLS
  users.nix                 # NEW: bree + root, SSH keys, zsh shell
  nix.nix                   # NEW: flakes, gc, autoUpgrade, sandbox, allowUnfree
  desktop.nix               # NEW: Plasma 6, SDDM wayland, printing, bluetooth, kdeconnect
  audio.nix                 # NEW: pipewire, low-latency, wireplumber BT codecs
  packages.nix              # NEW: systemPackages, fonts, direnv, gnupg, mtr, pcscd
  tailscale.nix             # from megakill-old
  gpu.nix                   # from megakill-old: AMD primary + Nvidia secondary, ROCm
  virtualisation.nix        # from megakill-old: libvirt, docker, kvmfr, VFIO specialisation
  bastion-nas.nix           # from megakill-old: NFS + CIFS mounts to bastion
  backup.nix                # from megakill-old: autoScrub + znapzend to bastion
  services.nix              # from megakill-old: minecraft, watchtower, microsocks
  modules/                  # unchanged (apple_fonts, kvmfr, vfio, libvirt, zenpower...)
  services/                 # from megakill-old (minecraft-atm9, minecraft-aof7)
```

## Module Details

### `megakill/disko.nix` - NEW

Declares the full disk layout for `/dev/nvme0n1`. The disko NixOS module reads this and generates all `fileSystems.*` entries automatically, so `hardware-configuration.nix` no longer needs them.

```nix
disko.devices = {
  disk.nvme0n1 = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        efi   = { size = "..."; type = "EF00"; content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot/efi"; }; };
        boot  = { size = "..."; content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; }; };
        cryptkey  = { size = "..."; content = { type = "luks"; name = "cryptkey"; ... }; };
        cryptswap = { size = "..."; content = { type = "luks"; name = "cryptswap"; keyFile = "/dev/mapper/cryptkey"; ... }; };
        zfs   = { size = "100%"; content = { type = "zfs"; pool = "rpool"; }; };
      };
    };
  };
  zpool.rpool = {
    type = "zpool";
    # @blank snapshot created here for root rollback
    postCreateHook = "zfs snapshot rpool/local/root@blank";
    datasets = {
      "local/root"    = { type = "zfs_fs"; mountpoint = "/"; };
      "local/nix"     = { type = "zfs_fs"; mountpoint = "/nix"; options.mountpoint = "legacy"; };
      "local/log"     = { type = "zfs_fs"; mountpoint = "/var/log"; };
      "safe/home"     = { type = "zfs_fs"; mountpoint = "/home"; };
      "safe/persist"  = { type = "zfs_fs"; mountpoint = "/persist"; };
    };
  };
};
```

The `lake` pool **is** declared in disko for documentation completeness, but as a standalone `zpool` entry not tied to any `disk` partition in the same config. This means:
- The disko NixOS module generates its `fileSystems` entries normally
- Running `disko --mode destroy,format,mount` on the nvme0n1 disk config will **never touch lake** since lake's drives are not listed under `disko.devices.disk`
- lake would only be affected if you explicitly ran disko against its own drives with a separate config

```nix
disko.devices.zpool.lake = {
  type = "zpool";
  mode = "mirror";  # documentation only
  datasets."data" = { type = "zfs_fs"; mountpoint = "/lake/data"; options = { mountpoint = "legacy"; }; };
};
```

`boot.zfs.extraPools = [ "lake" ]` stays in `zfs.nix` to ensure the pool is imported at boot (disko doesn't handle pool import, only fileSystems mounting).

### [`megakill/zfs.nix`](megakill/zfs.nix) - extend existing

Keep all current content. Add:
- `boot.zfs.extraPools = [ "lake" ];` — ensures lake is imported at boot
- `fileSystems."/lake/data" = { device = "lake/data"; fsType = "zfs"; options = [ "nofail" ]; };`

### `megakill/persist.nix` - REWRITTEN with impermanence

Replace all manual `fileSystems.* = { fsType = "none"; options = ["bind"]; }` with:

```nix
environment.persistence."/persist" = {
  hideMounts = true;
  directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/bluetooth"
    "/var/lib/tailscale"
    "/var/lib/libvirt"
    "/var/lib/containers"
    "/var/lib/AccountsService"
    "/var/lib/cups"
    "/var/lib/systemd/linger"
    "/var/db/sudo"
    "/var/spool"
    "/var/log"
    "/etc/ssh"
    "/etc/cups"
  ];
  files = [
    "/etc/machine-id"
  ];
};
# /etc/nixos bind is kept as a plain fileSystems entry since it's a bind to /home/bree, not /persist
```

Note: impermanence with `boot.initrd.systemd.enable = false` (our current setup) uses `boot.initrd.postMountCommands` internally for `neededForBoot` dirs — fully compatible.

### `megakill/networking.nix` - NEW
NM + networkd co-existence, resolved with DNSSEC + DoT, disable wait-online races, firewall on.

### `megakill/users.nix` - NEW
`users.mutableUsers = false`, `bree` with zsh + groups + SSH keys + hashedPassword, root hashedPassword.

### `megakill/nix.nix` - NEW
Flakes, sandbox, 60-day gc, autoUpgrade to `/etc/nixos#megakill` at 04:00, `allowUnfree`, `allowBroken`, `gitconfig` safe.directory.

### `megakill/desktop.nix` - NEW
Plasma 6, SDDM wayland, xserver, xkb us, CUPS + hplip, bluetooth, kdeconnect.

### `megakill/audio.nix` - NEW
pipewire + ALSA 32-bit + pulse compat + JACK, low-latency quantum config, wireplumber BT codec lua.

### `megakill/packages.nix` - NEW
Full `environment.systemPackages` list, fonts (apple_fonts, fira-code, source-*), fontconfig defaults, direnv, mtr, gnupg+pinentry-qt, pcscd, sysstat, zsh.

### `megakill/gpu.nix` - from megakill-old
`boot.initrd.kernelModules = ["amdgpu"]`, modesetting for AMD only, Nvidia secondary (no modesetting), ROCm OpenCL, `hardware.graphics` 32-bit + vulkan.

### `megakill/virtualisation.nix` - from megakill-old
libvirt + docker + kvmfr, `specialisation."VFIO"` with RTX 3090 passthrough, vhost_vsock, virt-manager, docker-compose. Imports from `modules/`.

### `megakill/backup.nix` - from megakill-old
`services.zfs.autoScrub` for rpool + lake, `services.znapzend` sending rpool/safe/* and lake/data to `ocean/backup/megakill` on bastion.

### `megakill/services.nix` - from megakill-old
Watchtower, microsocks SOCKS5, minecraft containers, firewall ports. Initially commented out in imports until virtualisation is stable.

## Import Order (incremental, one boot per step)

### Priority 0 — systemd initrd migration (do this first, in isolation)

Before building out any other modules, migrate `zfs.nix` off scripted initrd:

1. Remove `boot.initrd.systemd.enable = false`
2. Remove `boot.initrd.postMountCommands` and `boot.initrd.postResumeCommands`
3. Add equivalent `boot.initrd.systemd.services` entries:

```nix
boot.initrd.systemd.enable = true;

boot.initrd.systemd.services.close-cryptkey = {
  description = "Close cryptkey LUKS device after cryptsetup";
  wantedBy = [ "cryptsetup.target" ];
  after = [ "cryptsetup.target" ];
  before = [ "sysroot.mount" ];
  unitConfig.DefaultDependencies = false;
  serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.cryptsetup}/bin/cryptsetup close /dev/mapper/cryptkey"; };
};

boot.initrd.systemd.services.rollback = {
  description = "Rollback ZFS root to blank snapshot";
  wantedBy = [ "initrd.target" ];
  after = [ "zfs-import-rpool.service" ];
  before = [ "sysroot.mount" ];
  unitConfig.DefaultDependencies = false;
  serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.zfs}/bin/zfs rollback -r rpool/local/root@blank"; };
};
```

This is a small, isolated change with a clear pass/fail signal. Once the system boots cleanly with this, the rest of the restructure proceeds on the modern initrd path with no further constraints.

### Steps 1–14 — module restructure

```
configuration.nix always imports:
  hardware-configuration.nix   # step 1 - already working
  disko.nix                    # step 2 - replaces fileSystems in hw config
  zfs.nix                      # step 1 - already working (updated to systemd initrd above)
  persist.nix                  # step 3 - rewritten with impermanence
  networking.nix               # step 4
  users.nix                    # step 5
  nix.nix                      # step 6
  desktop.nix                  # step 7
  audio.nix                    # step 8
  packages.nix                 # step 9
  tailscale.nix                # step 10
  gpu.nix                      # step 11
  virtualisation.nix           # step 12
  bastion-nas.nix              # step 13
  backup.nix                   # step 14
# services.nix                 # step 15 (uncomment when ready)
```

## Key Constraints

- `boot.initrd.systemd.enable` — migration to `true` is **Priority 0** (see above). Neither impermanence nor disko impose a constraint here — both support systemd initrd natively. The only blocker was our own `postMountCommands`/`postResumeCommands` hooks, which are replaced by `boot.initrd.systemd.services` as the first step.
- `lake` — declared in disko for documentation, but its drives are not listed under `disko.devices.disk` so it is never touched by a reinstall
- The disko NixOS module only ever generates `fileSystems.*` entries at activation — it never partitions or formats anything
- Actual provisioning requires explicitly running `disko --mode destroy,format,mount` from a live USB — never on a running system

## Documentation

`docs/megakill-structure.md` will be written to the workspace documenting this layout, module rationale, and the step-by-step import order for future reference.
