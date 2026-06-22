# sops age keys for MicroVMs (deterministic, derived from a microvm key seed)

How per-VM sops age keys work in this repo: each MicroVM's key is *derived*
deterministically from a single microvm key seed, and the key image is built on
bastion automatically. You normally never run `age-keygen` per VM.

For background on sops-nix, age, and the recipient model, see
[`sops-nix-setup-plan.md`](./sops-nix-setup-plan.md).

---

## Model

```
secrets/microvm-key-seed.yaml   (sops; recipients: admin + recovery + bastion)
        |
        | derive unit decrypts it on demand, in memory, with bastion's ssh host
        | key (ssh-to-age -private-key); no standing /run/secrets plaintext
        v
derive-vm-key-<vm>.service  (HKDF-SHA256(seed, "sops-vm:<vm>") -> age identity)
        |
        | builds /persist/etc/sops/vm-keys/<vm>.img (label sops-<vm>, root:kvm 0440)
        v
microvm@<vm>.service        (mounts it read-only at /etc/sops/key.txt)
        |
        v
guest sops-install-secrets  -> /run/secrets/*
```

Key properties:

- **Deterministic**: the same VM name always derives the same key. A lost or
  deleted `<vm>.img` is rebuilt to the *same* identity on the next deploy, so
  secrets stay decryptable. Only the microvm key seed must be backed up.
- **No standing seed plaintext**: the seed is never installed to `/run/secrets`.
  Each `derive-vm-key-<vm>.service` decrypts it in memory (bastion's ssh host key,
  converted to an age identity by `ssh-to-age -private-key`), uses it to build the
  image, and discards it. The plaintext only exists in that unit's process during
  the boot-time image build.
- **Self-building**: bastion's `derive-vm-key-<vm>.service` runs before
  `microvm@<vm>.service` (see [bastion/modules/sops-vm-keys.nix](../bastion/modules/sops-vm-keys.nix)).
  It rebuilds the image only if missing or stale (compares `key.txt` read out of
  the image with `debugfs`, builds with `mke2fs -d`, no loop mount).
- **Declarative wiring**: marking a VM with `sops = true` in
  [bastion/vm-registry.nix](../bastion/vm-registry.nix) makes
  [bastion/modules/microvm-defaults.nix](../bastion/modules/microvm-defaults.nix)
  attach the `/etc/sops` volume and set `sops.age.keyFile`,
  `useSystemdActivation`, and `defaultSopsFile = secrets/bastion/<vm>.yaml`.
- **Generated policy**: the `.sops.yaml` rules for VM secrets are not hand-written.
  [scripts/sops-sync-recipients](../scripts/sops-sync-recipients) reads the same
  `sops = true` flag, derives each VM's key, and rewrites the marked block so every
  `secrets/bastion/<vm>.yaml` is encrypted to **admin + recovery + bastion + the
  VM's derived key**. bastion is a recipient of every VM secret (not just the seed),
  so it can read them directly when needed.

The derivation glue is [bastion/lib/derive-age-key.py](../bastion/lib/derive-age-key.py)
(HKDF -> Bech32 age identity; the public key is computed by `age-keygen -y`, so
the curve math isn't hand-rolled). The policy generator is
[bastion/lib/sops-sync-recipients.py](../bastion/lib/sops-sync-recipients.py).

---

## One-time: bootstrap the microvm key seed

As root on bastion (the seed's recipients include bastion so the host can derive
keys without your admin key present):

1. Add bastion as a recipient in [.sops.yaml](../.sops.yaml):

```bash
nix shell nixpkgs#ssh-to-age -c sh -c \
  'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'   # -> age1...; replace &bastion
```

2. Create the encrypted seed (32 random bytes, base64), on your workstation:

```bash
cd /persist/etc/nixos
SEED=$(head -c 32 /dev/urandom | base64)
nix shell nixpkgs#sops -c sops secrets/microvm-key-seed.yaml
# in the editor, add a single line:
#   microvm-key-seed: "<paste $SEED>"
```

Back up `$SEED` offline (password manager). It is the root of trust for every
VM key; `admin` and `recovery` can also decrypt `microvm-key-seed.yaml`.

---

## Adding sops to a VM

1. Flag it in [bastion/vm-registry.nix](../bastion/vm-registry.nix):

```nix
myvm = { tier = 1; index = 9; autostart = true; sops = true; ... };
```

2. Sync [.sops.yaml](../.sops.yaml). This derives the VM's key from the seed and
   fills the managed block with a `creation_rule` for `secrets/bastion/myvm.yaml`
   encrypted to **admin + recovery + bastion + the VM's derived key**:

```bash
cd /persist/etc/nixos
./scripts/sops-sync-recipients --policy-only   # secret file doesn't exist yet
```

   The generator owns only the block between the
   `# >>> sops-sync-recipients ... >>>` / `# <<< ... <<<` markers; the rest of
   `.sops.yaml` is hand-written. (To just inspect one VM's pubkey without
   rewriting anything, use `./scripts/sops-vm-pubkey myvm`, or `sops-vm-pubkey
   myvm` on bastion.)

3. Create the secrets file, then re-run the generator without `--policy-only` so
   the on-disk ciphertext picks up the full recipient set:

```bash
nix shell nixpkgs#sops -c sops secrets/bastion/myvm.yaml
./scripts/sops-sync-recipients        # rewrites policy + `sops updatekeys` each VM secret
```

4. Declare the secrets/templates the VM consumes in its host `.nix` (only
   `sops.secrets.*` / `sops.templates.*`; the plumbing comes from the module).
   Patterns for handing a secret to a service:
   - root reads it (e.g. systemd `EnvironmentFile`): default `root:root 0400`.
   - specific file format (e.g. ACME `PORKBUN_*`): `sops.templates.<name>` and
     consume `config.sops.templates."<name>".path`.
   - a non-root service reads the file directly (static user, e.g. coturn's
     `turnserver`): set `owner = "turnserver"` and point it at
     `config.sops.secrets."<name>".path`.

5. Commit, then deploy (see below).

---

## Deploy

```bash
cd /persist/etc/nixos
git add .                     # flake reads from git; new secrets files must be tracked
# get the commits onto bastion's checkout, then on bastion:
sudo nixos-rebuild switch --flake .#bastion   # installs the derive units
microvm -Ru myvm                              # derive unit builds the key image, VM restarts
```

`nixos-rebuild .#bastion` must precede `microvm -Ru` so the derive unit exists on
the host before the VM tries to mount its key image.

### Verify (inside the guest)

```bash
ls -l /etc/sops/key.txt                                # key volume mounted ro
systemctl status sops-install-secrets.service          # green
sudo cat /run/secrets/rendered/<template>              # template rendered, if any
ls -l /run/secrets/<secret>                            # owner as declared
```

On bastion you can also check `systemctl status derive-vm-key-<vm>`.

---

## Renaming a VM

The derivation input is the VM name, so renaming changes the derived identity.
This is a cheap re-key (no data loss, since `admin`/`recovery` always decrypt):

```bash
# rename in bastion/vm-registry.nix first, then:
git mv secrets/bastion/<old>.yaml secrets/bastion/<new>.yaml   # rename file
./scripts/sops-sync-recipients    # regenerates the block for <new> + re-keys the file
# deploy: nixos-rebuild .#bastion (rebuilds <new>.img) then microvm -Ru <new>
```

---

## Recovery

- **Lost a VM key image**: nothing to do beyond a redeploy. The derive unit
  rebuilds `<vm>.img` to the identical derived key, so secrets still decrypt.
- **Lost the microvm key seed but kept backups**: restore `microvm-key-seed` into
  `secrets/microvm-key-seed.yaml`; all VM keys re-derive identically.
- **Lost everything except git + an admin/recovery key**: generate a *new*
  microvm key seed, then run `./scripts/sops-sync-recipients` once. It re-derives
  every VM's recipient, rewrites `.sops.yaml`, and re-keys each
  `secrets/bastion/<vm>.yaml` (using your still-valid admin/recovery key).
  Redeploy.

Back up `/persist/etc/sops/` (the built images) and, above all, the microvm key seed.

---

## Manual fallback (no microvm key seed)

If you ever need a one-off random key not tied to the seed, the old manual flow
still works: `age-keygen`, build a labeled ext4 image with `mke2fs -d` (or a loop
mount), place it at `/persist/etc/sops/vm-keys/<vm>.img` as `root:kvm 0440`, and
add the printed pubkey to `.sops.yaml`. But then deletion is unrecoverable except
via the `admin`/`recovery` re-key path, which is why the derived model is
preferred.

---

## Notes

- **Image size:** 16 MB; the key file is tiny, ext4 minimums dominate.
- **Firecracker / zvols:** the in-guest contract (label `sops-<vm>`, `key.txt`,
  read-only `/etc/sops`) is unchanged; only the `microvm.volumes` backing differs.
- **Trust:** the microvm key seed can derive every VM key, so it's a single
  high-value secret. The trust boundary barely changes since bastion already
  builds and can read every VM.
