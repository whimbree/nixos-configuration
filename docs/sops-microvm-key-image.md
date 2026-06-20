# Creating a sops age-key image for a MicroVM

How to provision the per-VM age key that lets a MicroVM decrypt its sops
secrets at boot. Do this **once per VM** that needs secrets.

For background on sops-nix, age keys, and the overall recipient model, see
[`sops-nix-setup-plan.md`](./sops-nix-setup-plan.md). This doc is the concrete
runbook for the VM-key part only.

---

## Why a block device (and not virtiofs / ssh-to-age)

Physical hosts reuse their persistent `/etc/ssh/ssh_host_ed25519_key` via
`ssh-to-age`. MicroVMs can't: they regenerate SSH host keys on first boot, so
the key doesn't exist until *after* boot — but we need it *before* boot to
encrypt secrets for the VM.

So each VM gets a **dedicated, pre-generated age key**, delivered as a tiny
labeled ext4 image attached as a `microvm.volumes` block device (virtio-blk).
This is hypervisor-agnostic (works on cloud-hypervisor today, and on
firecracker/zvols later) and never depends on `/dev/vdX` ordering because we
mount by filesystem label.

Layout on the host (bastion):

```
/persist/etc/sops/vm-keys/<vm>.img    # ext4, label "sops-<vm>", contains key.txt
```

- `<vm>.img` is the block device the guest mounts read-only at `/etc/sops`.
- The private key lives only inside that image (and the offline recovery key —
  see below). The image is **never** committed to git.
- Only the `age1...` *public* key goes into `.sops.yaml`.

> The VM's private key lives on bastion rather than inside the guest. Since
> bastion already builds and fully controls every VM (disks, nix store,
> network), this doesn't change the trust boundary — and it lets us encrypt
> secrets for a VM before it ever boots.

---

## Prerequisites

- Run these as **root on bastion** (the host that runs the MicroVM).
- `/persist/etc/sops/` is on persistent storage and should be included in
  backups. Nothing under it is in git.

---

## 1. Generate the key + build the image (host-side, once per VM)

Replace `webrtc` with your VM name throughout.

```bash
VM=webrtc

# Directory owned root:kvm so microvm (in group kvm) can open the image.
install -d -m 0750 -o root -g kvm /persist/etc/sops /persist/etc/sops/vm-keys

# Generate the age key. Note the "Public key: age1..." line it prints.
nix shell nixpkgs#age -c age-keygen -o /tmp/$VM-age.txt
grep 'public key' /tmp/$VM-age.txt        # copy the age1... value for step 2

# Build a tiny labeled ext4 image holding key.txt.
truncate -s 16M /persist/etc/sops/vm-keys/$VM.img
nix shell nixpkgs#e2fsprogs -c mkfs.ext4 -q -L sops-$VM /persist/etc/sops/vm-keys/$VM.img

mnt=$(mktemp -d)
mount -o loop /persist/etc/sops/vm-keys/$VM.img "$mnt"
install -m 0400 /tmp/$VM-age.txt "$mnt/key.txt"
umount "$mnt"; rmdir "$mnt"
shred -u /tmp/$VM-age.txt                  # remove the plaintext key from /tmp

# The microvm runner (group kvm) needs to open the image; root owns it.
chown root:kvm /persist/etc/sops/vm-keys/$VM.img
chmod 0440 /persist/etc/sops/vm-keys/$VM.img
```

Key facts the VM config depends on:

- filesystem **label** = `sops-<vm>`
- the key file inside is named **`key.txt`**
- image is mounted **read-only** at `/etc/sops`

---

## 2. Add the VM's public key to `.sops.yaml`

Add the `age1...` from step 1 as a recipient, and a creation rule for the VM's
secrets file. Every secret is encrypted to `admin` (you) + `recovery` (offline
last-resort) + the VM.

```yaml
keys:
  - &admin     age1...        # you
  - &recovery  age1...        # offline last-resort key
  - &webrtc    age1...        # <-- paste the VM pubkey from step 1

creation_rules:
  - path_regex: secrets/webrtc\.yaml$
    key_groups:
      - age:
          - *admin
          - *recovery
          - *webrtc
```

If you change recipients for an *existing* secret file later, re-key it:

```bash
sops updatekeys secrets/webrtc.yaml
```

---

## 3. Create the encrypted secrets file

```bash
cd /persist/etc/nixos
nix shell nixpkgs#sops -c sops secrets/webrtc.yaml
```

Enter the secrets as plain key/value (quote values to be safe):

```yaml
porkbun-api-key: "pk1_..."
porkbun-secret-api-key: "sk1_..."
coturn-secret: "..."
```

sops encrypts the values on save. This file **is** committed to git.

---

## 4. Wire the key volume + sops into the VM config

In the VM's `.nix` (e.g. `bastion/hosts/t1/webrtc.nix`):

```nix
imports = [ inputs.sops-nix.nixosModules.sops ];

microvm.volumes = [
  # ... other volumes ...
  {
    image = "/persist/etc/sops/vm-keys/webrtc.img";
    mountPoint = "/etc/sops";
    label = "sops-webrtc";
    fsType = "ext4";
    size = 16;
    autoCreate = false;   # host provisions it, not microvm
    readOnly = true;      # cloud-hypervisor opens it O_RDONLY
  }
];

# Guest mounts the key volume read-only; nothing should ever write to it.
fileSystems."/etc/sops".options = [ "ro" "nosuid" "nodev" ];

sops = {
  defaultSopsFile = ../../../secrets/webrtc.yaml;
  # Install secrets via a systemd unit ordered after the key-volume mount and
  # after user creation (sysusers/userborn), instead of an early activation
  # script. This guarantees the key is mounted and any service users exist
  # before decryption / chown.
  useSystemdActivation = true;
  age = {
    keyFile = "/etc/sops/key.txt";
    sshKeyPaths = [ ];   # do NOT derive an age key from the VM's ssh host key
  };
  gnupg.sshKeyPaths = [ ];

  secrets."porkbun-api-key" = { };
  secrets."porkbun-secret-api-key" = { };
  # Set owner only when a non-root service reads the file directly (see note).
  secrets."coturn-secret" = { owner = "turnserver"; };
};
```

### Handing a secret to a service: three patterns

1. **Service reads as root** (e.g. systemd `EnvironmentFile`): leave the secret
   at its default `root:root 0400` — `/run/secrets/<name>`.
2. **Service needs a specific file format** (e.g. ACME's `PORKBUN_*` env file):
   render it with a template:

```nix
sops.templates."porkbun-credentials".content = ''
  PORKBUN_API_KEY=${config.sops.placeholder."porkbun-api-key"}
  PORKBUN_SECRET_API_KEY=${config.sops.placeholder."porkbun-secret-api-key"}
'';
# consume via: config.sops.templates."porkbun-credentials".path
```

3. **A non-root service reads the file directly** (e.g. coturn's `preStart`
   runs as `turnserver`): set `owner = "turnserver"` on the secret and point the
   service at `config.sops.secrets."coturn-secret".path`. This is safe because
   `useSystemdActivation` orders `sops-install-secrets.service` after user
   creation, so the user exists before sops chowns the file. (Only works for a
   service with a real static user — `DynamicUser` services need
   `LoadCredential` instead.)

---

## 5. Deploy + verify

```bash
cd /persist/etc/nixos
git add secrets/webrtc.yaml      # flake reads from git; the file must be tracked/staged
microvm -Ru webrtc               # rebuild + restart the VM
```

Inside the guest (`machinectl shell webrtc` or ssh):

```bash
ls -l /etc/sops/key.txt                              # key volume mounted (ro)
systemctl status sops-install-secrets.service        # should be green
sudo cat /run/secrets/rendered/porkbun-credentials   # template rendered
ls -l /run/secrets/coturn-secret                     # owned by the consuming user
```

---

## Key rotation

To roll a VM's age key (e.g. suspected compromise):

1. Generate a new key + image (step 1), overwriting `<vm>.img`.
2. Replace the VM's pubkey in `.sops.yaml` (step 2).
3. `sops updatekeys secrets/<vm>.yaml` to re-encrypt to the new recipient.
4. `git add` the changed secret file, then `microvm -Ru <vm>`.

The `admin` and `recovery` keys still decrypt throughout, so there's no lockout.

---

## Disaster recovery (lost VM key image)

If `/persist/etc/sops/vm-keys/<vm>.img` is lost, the encrypted secrets are still
recoverable because every file is also encrypted to `admin` and the offline
`recovery` key:

1. Generate a fresh key + image for the VM (step 1) and put its new pubkey in
   `.sops.yaml`.
2. With your `admin` (or `recovery`) private key available, run
   `sops updatekeys secrets/<vm>.yaml` to add the new VM key as a recipient.
3. `git add` + `microvm -Ru <vm>`.

Losing a VM key never loses the secret values — only that one VM's ability to
decrypt, which you restore by re-keying.

---

## Notes

- **Image size:** 16 MB is generous for a single key file; the minimum practical
  ext4 size is the constraint, not the key.
- **Firecracker / zvols:** the same image works as a raw block device. When
  moving to firecracker or zvol-backed volumes later, only the `microvm.volumes`
  backing changes — the in-guest contract (label `sops-<vm>`, `key.txt`,
  read-only `/etc/sops`) stays identical.
- **Backups:** include `/persist/etc/sops/` in bastion's backups so VM keys
  survive a host rebuild (or rely on the recovery-key re-key flow above).
