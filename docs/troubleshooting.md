# Troubleshooting

Known errors and their fixes across the homelab NixOS configs.

---

## libsForQt5 / extra-cmake-modules removed (NixOS 26.05)

**Error:**
```
error: The libsForQt5.extra-cmake-modules package and the corresponding
top-level extra-cmake-modules alias have been removed, as KDE Gear 5 and
Plasma 5 have reached end of life.
Please explicitly use kdePackages.extra-cmake-modules for the latest Qt 6-based version.
```

**Cause:** NixOS 26.05 removed all `libsForQt5.*` packages and the top-level aliases
that pointed at them (e.g. bare `extra-cmake-modules`). Anything still referencing
those aliases breaks at evaluation time.

**Fix:** Replace the bare alias with the Qt 6 equivalent:
```nix
# before
extra-cmake-modules

# after
kdePackages.extra-cmake-modules
```

Search the config for any other bare Qt 5 package names or `libsForQt5.*` references
and replace them with `kdePackages.<name>` or `qt6Packages.<name>` as appropriate.

**Affected hosts:** megakill

---

## libvirtd fails to start after nixos-rebuild — status=243/CREDENTIALS (NixOS 26.05 / libvirt 12.x)

**Error:**
```
libvirtd.service: Failed to determine local credential key: No such file or directory
libvirtd.service: Failed to set up credentials: No such file or directory
libvirtd.service: Failed at step CREDENTIALS spawning .../libvirtd: No such file or directory
```

or after partial fix:

```
libvirtd.service: Decryption failed (incorrect key?): error:00000000:lib(0)::reason(0)
libvirtd.service: Failed to set up credentials: Bad message
```

**Cause:** libvirt 12.x ships a `virt-secret-init-encryption.service` that creates a
per-machine secrets encryption key at `/var/lib/libvirt/secrets/secrets-encryption-key`,
encrypted with the systemd host credential key
(`/var/lib/systemd/credential.secret`). On a fresh install (or after a distro upgrade
to 26.05) neither file exists. The first `nixos-rebuild switch` runs
`virt-secret-init-encryption.service` before the host credential key exists, producing
a stale/invalid encrypted blob. Subsequent libvirtd starts then fail to decrypt it.

**Fix (one-time, run as root):**
```bash
# 1. Create the systemd host credential key (only needed once per machine)
systemd-creds setup

# 2. Delete the stale credential blob created before the host key existed
rm -f /var/lib/libvirt/secrets/secrets-encryption-key

# 3. Re-run the init service so it re-encrypts with the new host key
systemctl restart virt-secret-init-encryption.service

# 4. Start libvirtd — should succeed now
systemctl start libvirtd
```

The `credential.secret` warning ("not located on encrypted media") is harmless on
machines without a TPM; the software-backed key is sufficient.

**Affected hosts:** megakill
