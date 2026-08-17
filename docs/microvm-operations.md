# MicroVM creation and operations runbook

This runbook describes how MicroVMs on `bastion` are declared, installed,
started, updated, disabled, and removed. The most important distinction is
between the **host configuration** and each **guest configuration**:

- `nixos-rebuild switch --flake .#bastion` updates Bastion, its systemd units,
  networking, key-image builders, and the boot-time autostart policy. It does
  not build or update every guest.
- `microvm -u <name>` builds and selects one guest runner. It does not change
  Bastion's autostart policy.
- `systemctl start|stop|restart microvm@<name>.service` controls the installed
  runner without rebuilding it.

This separation is intentional. It prevents an ordinary Bastion rebuild from
building every guest's EROFS store image and exhausting host CPU and memory.

## Sources of truth

Every maintained VM has three declarations:

1. [The VM registry](../bastion/vm-registry.nix) owns operational metadata:
   tier, index, autostart, SOPS participation, observability, and description.
   The tier and index derive the IP address, MAC address, and TAP interface.
2. `bastion/hosts/t<tier>/<name>.nix` is the guest's NixOS configuration.
3. [flake.nix](../flake.nix) exposes the guest as
   `nixosConfigurations.<name>`.

Shared guest defaults live in
[microvm-defaults.nix](../bastion/modules/microvm-defaults.nix). Bastion's host
integration lives in [microvm.nix](../bastion/microvm.nix).

The registry is authoritative for boot-time policy, but it is not a process
manager. Changing `autostart` requires a Bastion rebuild because the value is
compiled into `microvms.target`.

## Runtime layout

Installed guests live under `/var/lib/microvms/<name>` on Bastion. Important
entries include:

| Entry | Purpose |
| --- | --- |
| `flake` | Flake reference used by `microvm -u`; normally `git+file:///etc/nixos`. |
| `current` | Symlink to the selected guest runner. A future start uses this runner. |
| `booted` | Symlink to the runner used by the currently running VM. It is removed when the VM stops. |
| `*.img` | Persistent guest volume images. These survive guest rebuilds and restarts. |
| sockets and PID files | Runtime state for the hypervisor and VirtioFS helpers. |

The host service is `microvm@<name>.service`. Its template starts the runner in
`current` and the helper units for TAP, VirtioFS, PCI devices, and the `booted`
symlink.

The selected and booted runners are protected from Nix garbage collection by
indirect roots under `/nix/var/nix/gcroots/microvm`. `microvm -c` creates these
for new VMs. Bastion's activation script supplies the same roots for VMs that
were migrated from declarative host management.

## Routine status commands

List every installed state directory:

```bash
find /var/lib/microvms -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
```

List loaded VM services and their states:

```bash
systemctl list-units --all 'microvm@*.service'
```

Show the VMs currently wanted at boot:

```bash
systemctl list-dependencies --plain microvms.target
```

Inspect one VM and its recent boot log:

```bash
systemctl --no-pager --full status microvm@<name>.service
journalctl -u microvm@<name>.service -b --no-pager -n 200
```

### Why `microvm -l` may print nothing

The pinned `microvm -l` implementation assumes every runner contains
`current/share/microvm/system`. Guests using `microvm.storeOnDisk` normally
omit that symlink so the runner does not retain the full uncompressed guest
closure. If the first installed VM lacks the symlink, `microvm -l` exits at its
first failed `readlink` without printing a useful error. This is a limitation
of the current command, not evidence that the VMs are missing. Use the `find`
and `systemctl` commands above.

## Creating a new VM

Use a staged rollout. Keep a new VM stopped until its storage, secrets, and
networking have been verified.

### 1. Choose its identity

Add the VM to [vm-registry.nix](../bastion/vm-registry.nix) with a unique tier
and index. Start with `autostart = false`:

```nix
example = {
  tier = 2;
  index = 3;
  autostart = false;
  sops = true;
  description = "Example service";
};
```

The name is operationally significant. It becomes the hostname, flake output,
state-directory name, systemd instance, derived SOPS identity, and part of
several volume and network identifiers. Renaming is therefore a migration,
not a cosmetic edit.

### 2. Add the guest configuration and flake output

Create `bastion/hosts/t2/example.nix`, reusing the shared defaults and patterns
from a VM with similar storage and exposure. Add the matching output to
[flake.nix](../flake.nix):

```nix
"example" = mkMicroVM ./bastion/hosts/t2/example.nix;
```

Review at least:

- guest memory, vCPU count, and hypervisor;
- persistent volume images and ownership;
- NFS/VirtioFS shares and mount ordering;
- firewall rules and listening addresses;
- observability and log persistence;
- reverse-proxy or Bastion forwarding dependencies;
- whether the service is safe to expose before application authentication is
  configured.

New files must be staged before evaluating a Git flake; untracked files are
not included in `git+file` flake source snapshots:

```bash
git add bastion/vm-registry.nix bastion/hosts/t2/example.nix flake.nix
```

Evaluate the guest declaration without installing it:

```bash
nix eval --raw .#nixosConfigurations.example.config.system.build.toplevel.drvPath
```

An optional full runner build is more expensive but validates the entire guest
and its store image:

```bash
nix build .#nixosConfigurations.example.config.microvm.declaredRunner \
  --no-link --max-jobs 3 --cores 4
```

### 3. Provision SOPS when required

For a VM with `sops = true`, follow
[sops-microvm-key-image.md](./sops-microvm-key-image.md). In summary:

1. Add the registry flag.
2. Generate the managed recipient policy.
3. Create and encrypt `secrets/bastion/<name>.yaml`.
4. Declare the guest's `sops.secrets` or templates.
5. Rebuild Bastion before the first VM start so
   `derive-vm-key-<name>.service` exists and can build the key image.

Do not hand-create a random VM key when the deterministic seed workflow is
available.

Stage the generated policy, encrypted secret, and the guest file again after
declaring its secret consumers. This second staging step matters because the
earlier index entry predates the SOPS edits, and Git flakes omit untracked
secrets entirely:

```bash
git add .sops.yaml secrets/bastion/example.yaml \
  bastion/hosts/t2/example.nix
git status --short
```

### 4. Commit and deploy the host integration

Use a Conventional Commit message:

```bash
git commit -m "feat(microvm): add example service"
sudo nixos-rebuild switch --flake .#bastion --max-jobs 3 --cores 4
```

This host rebuild installs `/etc/hosts` entries, SOPS derive units, host-side
mounts or forwarding, GC-root activation, and the VM service template. It does
not install the new guest runner.

### 5. Install and test the guest

Create the imperative installation once:

```bash
sudo microvm -c example
```

`microvm -c` builds the declared runner, creates
`/var/lib/microvms/example`, records the flake reference, and creates the Nix
GC roots. Do not run it again for an existing state directory; use `microvm -u`
for subsequent builds.

Start and inspect the VM:

```bash
sudo systemctl start microvm@example.service
systemctl --no-pager --full status microvm@example.service
journalctl -u microvm@example.service -b --no-pager -n 200
```

Verify application health, mounts, secrets, permissions, networking, and
persistent data before enabling autostart.

### 6. Enable it persistently

Change the registry entry to `autostart = true`, commit, and rebuild Bastion:

```bash
git add bastion/vm-registry.nix
git commit -m "chore(bastion): enable example MicroVM"
sudo nixos-rebuild switch --flake .#bastion --max-jobs 3 --cores 4
```

The switch adds `microvm@example.service` to the already-active
`microvms.target`. NixOS starts a newly wanted VM immediately; it will also be
started on subsequent host boots. Verify rather than assuming:

```bash
systemctl is-active microvm@example.service
```

If a start failed or was inhibited, retry it explicitly after reading the
journal:

```bash
sudo systemctl start microvm@example.service
```

Changing only `autostart` does **not** require `microvm -uR`; no guest
configuration changed.

## Starting and enabling existing VMs

### Temporary start

To start an installed VM now without changing its next-boot policy:

```bash
sudo systemctl start microvm@<name>.service
```

An active VM is treated as active by `microvm-update-all`, even when the
registry says `autostart = false`. On the next Bastion boot it remains stopped
unless the registry is changed.

### Persistent enable

1. Set `autostart = true` in the registry.
2. Commit the change.
3. Rebuild Bastion.
4. Verify that the switch started the newly wanted unit.

```bash
git add bastion/vm-registry.nix
git commit -m "chore(bastion): enable <name> MicroVM"
sudo nixos-rebuild switch --flake .#bastion --max-jobs 3 --cores 4
systemctl is-active microvm@<name>.service
```

Use `systemctl start` only as a fallback. Use `microvm -uR` as well only when
the guest configuration itself needs an update.

## Stopping and disabling a VM

### Temporary stop

```bash
sudo systemctl stop microvm@<name>.service
```

This does not change the registry. An autostart VM returns on the next host
boot. `microvm-update-all` will update the stopped guest without starting it.

### Persistent disable

Set `autostart = false`, commit, rebuild Bastion, and stop the existing runtime
instance explicitly:

```bash
git add bastion/vm-registry.nix
git commit -m "chore(bastion): disable <name> MicroVM"
sudo nixos-rebuild switch --flake .#bastion --max-jobs 3 --cores 4
sudo systemctl stop microvm@<name>.service
```

Removing a unit from `microvms.target` controls future starts; it does not
promise to stop a VM that is already running. Host forwarding units can also
depend on registry autostart. Check exposed ports after disabling externally
reachable services, and reboot if an older oneshot forwarding rule lacks a
runtime teardown path.

## Updating guests

### Update without changing runtime state

For a stopped VM, or when a maintenance restart will happen later:

```bash
sudo microvm -u <name>
```

This builds the guest serially under Bastion's Nix limits and moves `current`
to the resulting runner. It does not restart an active VM unless `-R` is
supplied.

### Update and restart when required

```bash
sudo microvm -uR <name>
```

The command compares `current` and `booted`. If the runner changed, it restarts
the active VM. If the VM is fully stopped and has no `booted` symlink, `-R`
starts it. For an intentionally stopped VM, prefer `microvm -u` followed by an
explicit `systemctl start` only when ready.

### Update the entire registered fleet

```bash
sudo microvm-update-all
```

The policy-aware updater processes every registered VM sequentially:

- active at its turn: run `microvm -uR`;
- inactive at its turn: run `microvm -u` and leave it inactive;
- missing installation: record a failure and continue;
- any failures: report all of them and exit non-zero at the end.

Runtime state deliberately wins over registry autostart in both directions.
This avoids starting an intentionally stopped VM while still preserving a VM
that was manually started despite `autostart = false`.

The same command runs from `microvm-weekly-update.timer` after the configuration
pull service has been attempted. The updater still runs if that pull fails, so
inspect both units when diagnosing a stale or failed scheduled update:

```bash
systemctl list-timers microvm-weekly-update.timer
journalctl -u nixos-config-git-pull.service --no-pager -n 100
journalctl -u microvm-weekly-update.service --no-pager -n 300
```

## Host changes versus guest changes

Use a Bastion rebuild for changes to:

- `vm-registry.nix`, including autostart or SOPS flags;
- Bastion networking, NFS exports, forwarding, or firewall rules;
- `microvm@.service` and instance-specific host dependencies;
- host SOPS key-image builders;
- host memory, ZFS, Nix, and MicroVM maintenance policy.

Use `microvm -u` or `microvm -uR` for changes to:

- `bastion/hosts/t*/<name>.nix` guest configuration;
- shared `microvm-defaults.nix` behavior used inside runners;
- guest packages, containers, mounts, services, users, or secrets wiring.

Some changes touch both sides. For example, adding SOPS to an existing VM
requires a Bastion rebuild to create the key-image unit and a guest update to
mount and consume that image. Deploy the host side first.

## Persistent volumes and resizing

`microvm.volumes.*.autoCreate = true` creates a missing image. Changing the
declared `size` does not enlarge an existing image. `fileSystems.<mount>.autoResize`
can grow the filesystem only after the backing block image itself has been
expanded and the VM has observed the new device size.

Before changing an existing volume:

1. Identify the exact image under `/var/lib/microvms/<name>`.
2. Stop the VM.
3. Take a ZFS snapshot or another recoverable backup.
4. Enlarge the backing image using an exact, validated path.
5. Start the VM and verify the filesystem size and service health.

Never delete or recreate a persistent image merely because `autoCreate` has a
larger declared size. Treat application databases, container storage, SSH host
keys, journals, and SOPS key images according to their individual recovery
requirements.

## Removing a VM

Removal is intentionally manual because the state directory may contain the
only copy of application data.

1. Set `autostart = false`, rebuild Bastion, and stop the VM.
2. Back up or snapshot `/var/lib/microvms/<name>`.
3. Remove host forwarding and DNS/proxy references.
4. Remove the registry entry, flake output, and guest configuration.
5. Rebuild Bastion and verify no systemd or network references remain.
6. Archive the state directory before considering permanent deletion.
7. Remove obsolete GC-root symlinks only after confirming no retained runner
   or rollback depends on them.

Do not recursively delete a VM state directory as part of an ordinary NixOS
switch; Nix declarations do not make state disposable.

## Troubleshooting

### VM does not start

```bash
systemctl --no-pager --full status microvm@<name>.service
journalctl -u microvm@<name>.service -b --no-pager -n 300
systemctl list-dependencies microvm@<name>.service
```

Then inspect failed helper units such as:

- `microvm-set-booted@<name>.service`;
- `microvm-tap-interfaces@<name>.service`;
- `microvm-virtiofsd@<name>.service`;
- `microvm-pci-devices@<name>.service`;
- `derive-vm-key-<name>.service` for SOPS-enabled guests.

### Instance unit says `bad-setting` or has no `ExecStart`

Host modules extending one specific VM service must use a drop-in:

```nix
systemd.services."microvm@<name>" = {
  overrideStrategy = "asDropin";
  after = [ "required-host-unit.service" ];
  requires = [ "required-host-unit.service" ];
};
```

Without `overrideStrategy = "asDropin"`, the generated instance unit shadows
the generic `microvm@.service` template and loses its runner `ExecStart`.

### `microvm -u` cannot find the VM

Confirm all of the following:

```bash
test -d /var/lib/microvms/<name>
test -L /var/lib/microvms/<name>/current
cat /var/lib/microvms/<name>/flake
nix eval --raw .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath
```

Use `microvm -c <name>` only if the installation directory genuinely does not
exist.

### Storage mount or disk failure

Read the complete error chain from the VM journal. A missing host image,
missing NFS source, stale permission, or a block device that was enlarged while
the VM remained running requires a different fix. Do not respond to a mount
failure by deleting the volume.

### Safe build limits

Bastion is a live ZFS and VM host. Preserve these limits during manual work:

```bash
sudo nixos-rebuild switch --flake .#bastion --max-jobs 3 --cores 4
```

Guest store-image construction is also capped at four EROFS workers. Run fleet
updates sequentially through `microvm-update-all`; do not background many
`microvm -u` processes.
