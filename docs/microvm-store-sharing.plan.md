# MicroVM Store Sharing — Spike / Future Work

## Problem

Current setup uses virtiofsd with `--cache=never` to share the host nix store
into each VM. This completely prevents KSM from running on any VM that has
virtiofsd attached.

virtiofsd uses `vhost-user`, which requires a shared memory region between the
virtiofsd process and cloud-hypervisor for the virtio queue. This region is
`MAP_SHARED` and cannot be marked `MADV_MERGEABLE`. Because the shared memory
region is part of the guest's physical address space, cloud-hypervisor cannot
mark the guest RAM slots as mergeable while vhost-user is active — the presence
of a single virtiofsd share disables KSM for the entire VM, not just the
virtiofsd pages.

Net result: KSM is completely disabled on every VM, regardless of `--cache`
setting or how many stores are shared. The `--cache=never` setting compounds
the problem by also ensuring nix store data never enters guest RAM, but it is
not the root cause — virtiofsd itself is.

## Goal

Share the nix store across VMs in a way that:
- Allows KSM to merge identical pages in guest RAM across VMs
- Preserves independent per-VM update capability (`microvm -u vmA` doesn't
  affect running vmB..vmZ)
- Doesn't require stopping all VMs simultaneously

## Why the obvious alternatives don't work

### NFS
NFS pages land in the guest as file-backed pages attributed to an NFS inode.
KSM only merges anonymous private pages (`MADV_MERGEABLE`). File-backed pages
are ineligible. Same KSM blackout as virtiofsd, plus network stack latency,
boot ordering fragility, and live store mutation risk during `nixos-rebuild`.

### Single shared erofs block device (naive)
A single erofs image of the union nix closure, passed to all VMs as a read-only
block device, would give automatic host page-cache deduplication (same inode →
one physical copy). But:
- Rebuilding any VM requires rebuilding the entire union image
- You cannot hot-swap a block device that 15 running VMs have open
- All VMs must stop to perform any update — destroys independent update model

## Proposed approach: per-VM erofs + KSM

**Phase 1 (pragmatic, no microvm.nix changes needed):**

Drop virtiofsd entirely. Each VM gets its own erofs store image (microvm.nix
already builds these via `storeDiskErofsFlags`). The VM mounts it locally as
`/nix/.ro-store`. Enable KSM on bastion:

```nix
# bastion/configuration.nix
hardware.ksm = {
  enable = true;
  sleep = 50; # ms between scans — tune based on CPU budget
};
```

Since all VMs are built from the same nixpkgs revision, their store images have
largely identical content. KSM running on the host merges identical anonymous
pages in guest RAM across VMs. Independent updates are preserved because each
VM has its own image — `microvm -u vmA` replaces only vmA's image.

Expected RAM savings: ~60–80% of what a perfect shared image would give, with
zero microvm.nix changes and full update independence.

Disk cost: each VM's erofs image is ~3–5 GB. With 15 VMs that's ~50–75 GB.
ZFS compression on the image files brings this down significantly (nix store
content compresses extremely well with zstd).

**Phase 2 (tall hill — ZFS-only personal fork, probably never upstreamable):**

ZFS clone-based shared store with independent update capability:

1. Build one canonical erofs image of the union closure of all VM stores.
   Store it as a ZFS dataset, e.g. `rpool/microvm-store/base`.
2. Snapshot: `zfs snapshot rpool/microvm-store/base@<nixpkgs-rev>`
3. Each VM gets a ZFS clone of that snapshot:
   `zfs clone rpool/microvm-store/base@<rev> rpool/microvm-store/<vmName>`
   Clones are copy-on-write — near-zero disk cost at creation time.
4. Each VM is given its clone as a read-only block device (replacing virtiofs).
5. On `microvm -u vmA`:
   - Build new erofs image for vmA's updated closure
   - If the shared base changed: create a new snapshot, re-clone for vmA only
   - vmB..vmZ keep their old clones and keep running — no disruption

This achieves:
- Host page-cache automatic deduplication (same file for clones that haven't
  diverged = same inode = one physical copy)
- KSM on top for any remaining diverged pages
- Full independent update capability
- No virtiofsd, no shared memory regions

### Implementation work required (Phase 2)

**microvm.nix changes:**
- New volume type: `readOnlyShared` — points to an external image path rather
  than a VM-local image. The image is not lifecycle-managed per-VM.
- `microvm -u` hook calls the shared image management script before restarting
  the target VM.

**Shared image lifecycle management:**

The canonical erofs image must be rebuilt when VM closures diverge far enough
from the base that the per-VM delta erofs images become large. A simple
heuristic: track which store paths are in the base image vs. which are needed
by current VM closures; if `|new paths| / |base paths| > threshold` (e.g. 20%),
rebuild the base.

Concretely:
- On every `nixos-rebuild`, compute the union closure of all VMs
- Diff against the store paths recorded in the current base image manifest
- If divergence exceeds threshold: rebuild base image, re-clone all VMs on
  next restart (don't force-restart running VMs; old clones remain valid)
- Collect stale clones (VMs that have been removed) on a separate GC pass

Union closure computation in `flake.nix`:
```nix
sharedStorePaths = lib.unique (lib.concatMap
  (vm: vm.config.system.requisites)
  (builtins.attrValues nixosConfigurations));
```

**Why Phase 2 is probably not upstreamable:**

The ZFS clone approach only meaningfully pays off on ZFS or btrfs (reflinking).
On ext4 the "clone" is just a full `cp` — you get per-VM disk duplication with
no CoW benefit, which defeats the entire point. Add the divergence tracking,
versioned base images, and GC policy on top, and the complexity-to-benefit
ratio is too high for the general case. Upstream maintainers would reasonably
ask "why not just use virtiofs?" — and on ext4, that's a fair question.

Phase 2 is worth doing in this personal fork where ZFS is a given. It is
unlikely to be accepted upstream in this form.

## RAM budget estimate (bastion)

Assuming 15 VMs at 512 MB default guest allocation. Numbers are rough order-of-
magnitude estimates, not benchmarks.

| Approach                | Guest RAM (physical) | Host virtiofsd overhead | KSM                          |
|-------------------------|----------------------|-------------------------|------------------------------|
| virtiofsd --cache=never | 15 × 512 MB = 7.5 GB | ~15 × 100 MB ≈ 1.5 GB  | **Completely disabled**      |
| Per-VM erofs + KSM      | 15 × 512 MB = 7.5 GB | None                    | Full — process + store pages |
| ZFS clone shared image  | 15 × 512 MB = 7.5 GB | None                    | Full + host page cache dedup |

**virtiofsd kills KSM entirely.** Any VM with a virtiofsd share cannot
participate in KSM at all — not just for nix store pages, but for every page
in that VM. With 15 VMs all running virtiofsd, KSM is yielding nothing.

**virtiofsd process overhead:** with `threadPoolSize = 6`, each virtiofsd
instance has 6 worker threads plus vhost-user shared memory buffers. ~100 MB
per VM is a rough estimate — measure with `smem` on bastion for real numbers.
At 15 VMs this is ~1.5 GB of host RAM consumed by daemon overhead alone.

Phase 1 (drop virtiofsd, per-VM erofs, enable KSM) eliminates both costs:
the daemon overhead disappears and KSM is unblocked across all VMs for the
first time. Phase 2 is the theoretical ceiling but Phase 1 is the real unlock.

## Bonus: dropping virtiofsd unlocks Firecracker

virtiofsd is the primary reason cloud-hypervisor is required. Firecracker's
device model is intentionally minimal — virtio-blk, virtio-net, virtio-vsock,
virtio-balloon, virtio-rng — with no virtio-fs support. That's not a
limitation for the erofs-only setup.

Benefits of switching to Firecracker (microvm.nix already supports it):
- **Lower VMM overhead per VM** — Firecracker's process is significantly
  leaner than cloud-hypervisor; meaningful at 15+ VM density
- **~125ms boot times** — built for Lambda-scale density at AWS
- **Smaller attack surface** — minimal device model by design, less exposed
  hypervisor code per VM
- **KSM fully compatible** — Firecracker does not require `shared=on` memory

The only things lost from cloud-hypervisor: VFIO passthrough and PCIe hotplug.
**One exception:** the jellyfin microVM is planned to receive GTX 1060 passthrough
for NVENC hardware transcoding (the 1060 is installed on bastion but not yet
wired up, and is not used for display). Jellyfin stays on cloud-hypervisor for
that reason. All other VMs can move to Firecracker.

Switching hypervisor is `microvm.hypervisor = "firecracker"` in
`microvm-defaults.nix` once virtiofsd is gone.

## Realistic upstream contribution

Rather than the full Phase 2 mechanism, the upstreamable contribution is
smaller and more useful: **document the KSM tradeoff and surface it as an
explicit option**.

Currently the interaction between `--cache=never`, virtiofsd, and KSM requires
reading kernel internals to understand. A realistic PR to upstream microvm.nix:

1. Add a note in the virtiofs documentation that `--cache=never` eliminates
   guest-side nix store caching and therefore KSM merge opportunities.
2. Recommend per-VM erofs images + `hardware.ksm` on the host as the
   KSM-friendly alternative.
3. Optionally expose `microvm.store.mode = "virtiofs" | "image"` to make the
   choice explicit with a comment about the RAM/KSM tradeoff.

That's a realistic PR with a clear rationale that doesn't require new
infrastructure.

## References

- KSM docs: https://www.kernel.org/doc/html/latest/admin-guide/mm/ksm.html
- microvm.nix volumes: https://astro.github.io/microvm.nix/options.html
- erofs: https://erofs.docs.kernel.org/
