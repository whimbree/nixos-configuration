# sops-nix Setup Plan

Status: **proposal / not yet implemented**. This is a review document. No
config files have been changed.

This plan is tailored to this repo: 3 physical hosts (`bastion`, `megakill`,
`wheatley`) built via `mkHost`, and 16 MicroVMs built via `mkMicroVM`, with
`bastion` acting as the secrets hub for the VMs.

---

## 0. Background: what is an "age key" (and what is sops-nix)?

**The problem.** You have secrets (API keys, passwords, `.env` files). You want
them version-controlled in this git repo, but you obviously can't commit them in
plaintext. So you encrypt them. Today this repo dodges the problem by keeping
secrets *outside* git (on-disk files under `/services/`, `.env` files, virtiofs
shares) plus some plaintext passwords committed directly in `.nix` files.

**sops** ("Secrets OPerationS", by Mozilla) is a tool that encrypts the
*values* in a YAML/JSON file while leaving the *keys* (the field names)
readable. So a file like this stays diff-friendly and reviewable:

```yaml
porkbun_api_key: ENC[AES256_GCM,data:9f3a...,tag:...]
porkbun_secret:  ENC[AES256_GCM,data:1b77...,tag:...]
```

**age** is the encryption backend sops uses here. age is a modern, simple
encryption tool. An **age key** is just a keypair:

- A **public key** (looks like `age1qz...`) — anyone can have it. You encrypt
  *to* a public key. You can list many public keys as recipients, and any one of
  the matching private keys can decrypt.
- A **private key** (looks like `AGE-SECRET-KEY-1...`) — kept secret. Used to
  *decrypt*.

So the model is: we encrypt each secret file to a set of recipient public keys.
The recipients are (a) **you**, so you can always edit secrets, and (b) **each
machine that needs to read that secret**, so it can decrypt at boot.

**Where do machine keys come from?** Every Linux box already has an SSH host key
at `/etc/ssh/ssh_host_ed25519_key`. The tool `ssh-to-age` converts that existing
SSH key into an age key. This is the nice part: physical hosts don't need any
*new* secret material — we reuse the SSH host key they already persist.

**sops-nix** is the NixOS integration. You declare secrets in Nix:

```nix
sops.secrets.porkbun_api_key = { };
```

and at activation time sops-nix decrypts the file using the machine's private
key and drops the plaintext at `/run/secrets/porkbun_api_key` (on tmpfs, root
readable by default, mode/owner configurable). Your services read that path.
The plaintext never touches disk persistently and never enters the nix store.

**You do not strictly need to understand age beyond this.** Practically you will
run three commands ever: generate your key once, `sops secrets/x.yaml` to edit
(it decrypts in `$EDITOR`, re-encrypts on save), and `sops updatekeys` after
changing recipients.

---

## 1. Key model for this repo

| Identity | Key source | Role |
|----------|-----------|------|
| **You (admin)** | a personal age key on your laptop/workstation | recipient on *every* secret, so you can always edit |
| **bastion / megakill / wheatley** | `ssh-to-age` of each host's `/etc/ssh/ssh_host_ed25519_key` | decrypt that host's secrets at boot |
| **each MicroVM** | a dedicated, pre-generated age key delivered via a **block device** (see §4) | decrypt that VM's secrets at boot |

### Why VMs are different

Physical hosts persist their SSH host key, so their age key is stable and known
ahead of time — perfect for `ssh-to-age`.

MicroVMs currently *generate* their SSH host keys randomly **on first boot**
(`generate-ssh-host-keys.service` in `bastion/modules/microvm-defaults.nix`
writes into `ssh-host-keys.img`). That's a chicken-and-egg problem: to encrypt a
secret *for* a VM you need its public key, but its key doesn't exist until it
has booted. So for VMs we **pre-generate a dedicated age key per VM** and deliver
it into the guest ourselves. See §4.

---

## 2. Your personal age key (one-time, do this first)

You don't have one yet, so generate one. Pick the method you prefer:

**Option A — fresh age key (simplest):**

```bash
nix shell nixpkgs#age -c age-keygen -o ~/.config/sops/age/keys.txt
# prints: Public key: age1........
```

`keys.txt` holds your *private* key — back it up somewhere safe (password
manager). The printed `age1...` line is your *public* key; that's what goes in
`.sops.yaml`. Losing this key only means you re-key from a host key; it's not
catastrophic, but treat it like an SSH private key.

**Option B — derive from your existing SSH key (no new secret to back up):**

```bash
nix shell nixpkgs#ssh-to-age -c sh -c \
  'ssh-to-age < ~/.ssh/id_ed25519.pub'        # public (for .sops.yaml)
# and for the private side, sops reads it from:
mkdir -p ~/.config/sops/age
nix shell nixpkgs#ssh-to-age -c \
  ssh-to-age -private-key -i ~/.ssh/id_ed25519 -o ~/.config/sops/age/keys.txt
```

Recommendation: **Option A**. It decouples "can I decrypt SSH" from "can I edit
secrets," and is the conventional sops-nix workflow.

---

## 3. Collecting host public keys

For each physical host, get its age public key (run on each host, or fetch the
public SSH key over the network):

```bash
# on the host:
nix shell nixpkgs#ssh-to-age -c sh -c \
  'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'
# -> age1<bastion>, age1<megakill>, age1<wheatley>
```

These are *public* keys, safe to commit in `.sops.yaml`.

---

## 4. MicroVM key delivery via block device (your preferred direction)

You said you'd rather pass a **block device** to each VM than use virtiofs (which
is how `/services/traefik/secrets` is shared into `gateway`/`webrtc` today). Good
— we'll build VM secrets on a block device from the start so there's no virtiofs
detour to undo later. This mirrors the existing `ssh-host-keys.img` volume
pattern already in `microvm-defaults.nix`.

### Design

For each VM, bastion owns a tiny ext4 image containing that VM's age **private**
key:

```
/persist/etc/sops/vm-keys/<vm>.img    # ext4, contains key.txt (the AGE-SECRET-KEY)
/persist/etc/sops/vm-keys/<vm>.pub    # the age1... public key (for .sops.yaml)
```

The VM mounts it as a microvm volume and points sops at it:

```nix
# in each VM (or generalized in microvm-defaults.nix, gated on a flag):
microvm.volumes = [{
  image = "/persist/etc/sops/vm-keys/${vmName}.img";
  mountPoint = "/etc/sops";
  size = 4;                 # MB; key file is tiny
  fsType = "ext4";
  autoCreate = false;       # provisioned by bastion, not blank-created
}];

sops.age.keyFile = "/etc/sops/key.txt";
sops.age.sshKeyPaths = [];  # don't try to derive from VM ssh host key
sops.gnupg.sshKeyPaths = [];
```

### Provisioning the per-VM key images (bastion-side, one-time per VM)

A helper script (to be added under `scripts/`) will, for each VM:

```bash
mkdir -p /persist/etc/sops/vm-keys
age-keygen -o /tmp/<vm>.txt                       # private key
grep 'public key' /tmp/<vm>.txt | awk '{print $4}' > /persist/etc/sops/vm-keys/<vm>.pub
# build a tiny ext4 image holding key.txt:
truncate -s 4M /persist/etc/sops/vm-keys/<vm>.img
mkfs.ext4 -q /persist/etc/sops/vm-keys/<vm>.img
mount -o loop /persist/etc/sops/vm-keys/<vm>.img /mnt
install -m 600 /tmp/<vm>.txt /mnt/key.txt
umount /mnt && shred -u /tmp/<vm>.txt
```

The `.pub` files feed `.sops.yaml`. The `.img` files live on bastion's
persistent storage, never in git.

> **Note on this trade-off:** the VM's private key now lives on the bastion host
> rather than being generated inside the guest. Since bastion already builds and
> fully controls every VM (it owns the disks, the nix store, the network), this
> doesn't materially change the trust boundary — bastion can already read any
> VM's data. The benefit is we can encrypt secrets for a VM before it ever boots.

> **Alternative considered (rejected for now):** pre-generate each VM's *SSH host
> key*, bake it into `ssh-host-keys.img`, and use `ssh-to-age` on it. This avoids
> a second key file but couples SSH identity to secret-decryption identity and
> requires reworking `generate-ssh-host-keys.service`. The dedicated block-device
> key is cleaner and matches your stated direction.

---

## 5. `.sops.yaml` (the recipient policy)

Lives at repo root. It maps file paths to which public keys they're encrypted
for. Anchors keep it DRY.

```yaml
keys:
  # people
  - &admin       age1ADMIN_PUBLIC_KEY
  # physical hosts
  - &bastion     age1BASTION
  - &megakill    age1MEGAKILL
  - &wheatley    age1WHEATLEY
  # microvms (from /persist/etc/sops/vm-keys/<vm>.pub)
  - &gateway     age1GATEWAY
  - &immich      age1IMMICH
  - &fluxer      age1FLUXER
  # ... one per VM that needs secrets

creation_rules:
  # shared across all physical hosts (e.g. user passwords)
  - path_regex: secrets/common\.yaml$
    key_groups:
      - age: [*admin, *bastion, *megakill, *wheatley]

  - path_regex: secrets/bastion\.yaml$
    key_groups:
      - age: [*admin, *bastion]

  - path_regex: secrets/gateway\.yaml$
    key_groups:
      - age: [*admin, *gateway]

  - path_regex: secrets/immich\.yaml$
    key_groups:
      - age: [*admin, *immich]

  # ... one rule per secrets file
```

Rule of thumb: **a secret is encrypted only to the machine(s) that read it, plus
you.** After changing recipients, run `sops updatekeys secrets/<file>.yaml`.

---

## 6. Flake + module wiring

### 6.1 Add the input (`flake.nix`)

```nix
inputs = {
  # ...
  sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### 6.2 Wire the module into both builders (`flake.nix`)

Physical hosts — add to the `modules` list in `mkHost`:

```nix
modules = (import ./profiles)
  ++ [ ./modules/lix.nix inputs.sops-nix.nixosModules.sops ]
  ++ extraModules ++ modules;
```

MicroVMs — add to the `modules` list in `mkMicroVM`:

```nix
modules = [
  microvm.nixosModules.microvm
  ./bastion/modules/microvm-defaults.nix
  ./modules/lix.nix
  inputs.sops-nix.nixosModules.sops
  path
];
```

(`inputs` is already in scope via `@inputs`; `sops-nix` will flow through.)

### 6.3 Shared sops defaults

- **Physical hosts:** add a small `modules/sops.nix` (imported via `profiles/`)
  setting the default decryption key source:

```nix
{ ... }: {
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # default file can be per-host; usually set sops.defaultSopsFile per host
}
```

- **MicroVMs:** set `sops.age.keyFile = "/etc/sops/key.txt"` and the block-device
  volume from §4, generalized in `microvm-defaults.nix` behind a per-VM flag so
  VMs without secrets don't get an empty key volume.

---

## 7. Impermanence / persistence considerations

- **megakill** (impermanence): age key derives from `/etc/ssh/ssh_host_ed25519_key`,
  which is already persisted. Decrypted secrets land in `/run/secrets` (tmpfs) —
  nothing extra to persist. ✅ Nothing to add.
- **bastion / wheatley:** SSH host keys already persisted via `/persist/etc/ssh`
  bind mounts. ✅
- **VM key images** live under `/persist/etc/sops/vm-keys/` on bastion — persistent
  and outside git. Add `/persist/etc/sops/` to backups.
- `.gitignore`: add `secrets/*.img`, `*.txt` age keys, and keep `**/.env` ignored.
  (The encrypted `secrets/*.yaml` files *are* committed — that's the point.)

---

## 8. Proof of concept (validates the whole chain before migrating anything)

1. Do §2 (your key), §3 (bastion host key), §5 (minimal `.sops.yaml` with just
   `admin` + `bastion`), §6.1/§6.2 (input + wiring for bastion only).
2. Create `secrets/bastion.yaml`:

```bash
sops secrets/bastion.yaml
# add: hello: world
```

3. In `bastion/configuration.nix` (temporarily):

```nix
sops.defaultSopsFile = ../secrets/bastion.yaml;
sops.secrets.hello = { };
```

4. `nixos-rebuild switch --flake .#bastion` (or build + deploy as you normally do).
5. Verify: `sudo cat /run/secrets/hello` → `world`. ✅
6. Remove the throwaway `hello` secret.

Once this works end-to-end, the rest is just repeating the pattern.

---

## 9. Migration order (highest value first)

Each phase is independent and shippable.

1. **Foundation** — §2–§6 + §8 PoC.
2. **Porkbun + coturn** — `gateway`, `webrtc`, and `wheatley` nginx ACME. This
   replaces the plaintext `/services/traefik/secrets/*` virtiofs share with sops
   secrets + the §4 block device. Files involved:
   - `bastion/hosts/t0/gateway.nix` (the `/host-secrets` virtiofs share + the
     oneshot that writes `/var/lib/acme/porkbun-credentials`)
   - `bastion/hosts/t1/webrtc.nix` (coturn secret)
   - `wheatley` nginx (`/services/nginx/porkbun-credentials`)
   - Pattern: `sops.secrets.porkbun_api_key`, then either
     `sops.templates."porkbun-credentials".content` to render the exact file
     format ACME expects, or point the consumer at `config.sops.secrets.X.path`.
3. **`.env` files** — `immich`, `fluxer` (and later jitsi/crowdsec/slskd/invidious
   if revived). Use `sops.templates` to render a full `.env`, or set
   `systemd.services.<svc>.serviceConfig.EnvironmentFile = config.sops.secrets.X.path`
   where the service supports a key=val env file.
4. **Hashed user passwords** — move `bree`/`root` `hashedPassword` out of
   `profiles/users.nix` into `secrets/common.yaml` using
   `sops.secrets."bree-password" = { neededForUsers = true; }` +
   `users.users.bree.hashedPasswordFile = config.sops.secrets."bree-password".path;`
   (`neededForUsers` decrypts early, before user creation.)
5. **Hardcoded DB / RCON / container passwords** in VM configs (nextcloud,
   photoprism, minecraft RCON, immich postgres, etc.).
6. **Optional:** WireGuard `wg0.conf` (airvpn VMs) and megakill `~/.smbcredentials`.

---

## 10. Day-to-day commands (cheat sheet)

```bash
sops secrets/gateway.yaml        # edit (decrypts to $EDITOR, re-encrypts on save)
sops -e -i secrets/gateway.yaml  # encrypt in place (rarely needed manually)
sops updatekeys secrets/gateway.yaml   # re-encrypt after changing recipients in .sops.yaml
```

You never manually decrypt on a host — sops-nix does that at activation.

---

## 11. Open questions for you

1. **Personal age key method** — fresh age key (Option A) vs derive from your SSH
   key (Option B)? Plan assumes A.
2. **One secrets file per VM vs grouped** — I assumed per-VM files
   (`secrets/<vm>.yaml`) for blast-radius isolation. Could also do one big
   `secrets/vms.yaml` encrypted to all VMs (simpler, weaker isolation).
3. **VM key image size / location** — assumed 4 MB ext4 at
   `/persist/etc/sops/vm-keys/`. OK?
4. **Migration scope to start** — confirm we begin with Foundation (§8) then
   Porkbun (phase 2), which gives the biggest immediate win.
```
