# Megakill Phase 2 — Shared modules across bastion + megakill

## Goal
Eliminate duplication between `bastion/` and `megakill/` by extracting
shared configuration into `modules/`. Phase 1 must be complete and megakill
must be booting cleanly before starting this.

## Principle
Shared modules declare the base. Hosts extend or override via NixOS's
normal attribute merge semantics (lists append, scalars use mkDefault/mkForce).
Don't over-abstract — only extract things that are truly identical or
structurally identical with minor host-specific differences.

---

## Proposed shared modules

### `modules/common.nix`
Things identical on every host:
```nix
nix.gc = { automatic = true; randomizedDelaySec = "15m"; options = "--delete-older-than 60d"; };
nix.settings.experimental-features = [ "nix-command" "flakes" ];
nix.settings.sandbox = true;
nixpkgs.config.allowUnfree = true;
services.sysstat.enable = true;
systemd.settings.Manager.DefaultTimeoutStopSec = "30s";
environment.etc."gitconfig".text = ''
  [safe]
    directory = /etc/nixos
'';
```

### `modules/ssh.nix`
SSH daemon config identical across hosts:
```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    LogLevel = "VERBOSE";
  };
};
```

### `modules/networking-base.nix`
DNS-over-TLS + systemd-networkd setup used by both hosts:
```nix
networking.useNetworkd = true;
systemd.network.enable = true;
systemd.network.wait-online.enable = lib.mkForce false;
systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
networking.nameservers = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
services.resolved = {
  enable = true;
  settings.Resolve = {
    DNSSEC = true;
    Domains = [ "~." ];
    FallbackDNS = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    DNSOverTLS = true;
  };
};
```
Note: bastion adds `MulticastDNS = false` (lets avahi own mDNS exclusively).
megakill does not need that override — resolved handling mDNS is fine on desktop.

### `modules/users.nix`
Base user definition shared across hosts. Hosts add their own `extraGroups`.
```nix
users.mutableUsers = false;
users.users.bree = {
  isNormalUser = true;
  home = "/home/bree";
  shell = pkgs.zsh;   # megakill only — bastion doesn't set this
  openssh.authorizedKeys.keys = [ ... all shared keys ... ];
  hashedPassword = "...";
};
users.users.root.hashedPassword = "...";
programs.zsh.enable = true;           # megakill only
environment.shells = [ pkgs.zsh ];    # megakill only
```
Problem: `shell = pkgs.zsh` is megakill-specific (bastion uses default shell).
Options:
  a) Keep shell out of the shared module, set it per-host
  b) Use `lib.mkDefault pkgs.bash` in shared, megakill overrides with `pkgs.zsh`
  Option (b) is cleaner.

### `modules/autoUpgrade.nix` — probably not worth it
`system.autoUpgrade` differs only in `flake` target and `flags`. Not enough
shared structure to justify a module. Leave it per-host.

---

## Migration steps

1. Create each module file under `modules/`
2. Update `bastion/configuration.nix` to import new shared modules, remove duplicated config
3. Update `megakill/configuration.nix` to import new shared modules, remove duplicated config
4. `nixos-rebuild build` both hosts (don't switch yet) and diff the resulting system closure
   to verify no unintended changes
5. Switch bastion first (lower risk — headless server, can SSH in to recover)
6. Switch megakill

## Risk areas
- `users.users.bree` merging: NixOS merges attrsets from multiple modules.
  `extraGroups` lists append cleanly. `hashedPassword` will conflict if set
  in two places — keep it only in the shared module.
- `networking.nameservers` is a list — if both the shared module and a host
  set it, they'll concatenate. Use `lib.mkForce` in the shared module or
  don't set it per-host at all.
- `systemd.network.wait-online.enable = lib.mkForce false` — the `mkForce`
  must survive the shared→host import chain. Test with `nix eval` before switching.

## What stays per-host (never shared)
- `networking.hostName`, `networking.hostId`
- `system.stateVersion`
- `system.autoUpgrade.flake`
- `boot.*` (hardware-specific)
- `fileSystems`, `swapDevices`
- `hardware.cpu.*`
- Host-specific services (microvm, NAS exports, etc.)
