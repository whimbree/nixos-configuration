# Jellyfin MicroVM — GTX 1060 VFIO Passthrough

## Goal

Pass the GTX 1060 installed on bastion through to the jellyfin microVM so that
Jellyfin can use NVENC/NVDEC for hardware transcoding instead of burning 20
vCPUs on software decode.

## Context

- The 1060 is physically installed in bastion but has no display output connected
  and is not used for any host workload. It can be permanently bound to vfio-pci
  at boot — no dynamic detach/attach scripts needed (unlike megakill's 3090,
  which must be reclaimed from the Nvidia driver on demand).
- Jellyfin stays on cloud-hypervisor (the only VM that does) because VFIO
  passthrough requires it. All other VMs can migrate to Firecracker.
- Jellyfin already has virtiofsd for its config share, so the cloud-hypervisor
  + shared memory requirement is already in place.

## Prerequisites — gather first

Before writing any Nix config, boot bastion and collect:

```bash
# Find the 1060's PCI IDs
lspci -nn | grep -i nvidia

# Check its IOMMU group — must be alone (or with just its own audio function)
for d in /sys/kernel/iommu_groups/*/devices/*; do
  echo "Group $(echo $d | cut -d/ -f5): $(lspci -nns $(basename $d))";
done | grep -i nvidia
```

If the 1060 shares an IOMMU group with unrelated devices (e.g. PCIe root port,
other cards), ACS patching or a different slot may be required. This must be
resolved before proceeding.

Expected IDs for a GTX 1060:
- GPU function: `10de:1c02` (6GB) or `10de:1c03` (3GB) — verify with lspci
- Audio function: `10de:10f1`

Also confirm bastion's CPU/IOMMU type:
```bash
lscpu | grep -i "model name"   # Intel → intel_iommu, AMD → amd_iommu
```

## Step 1 — Enable IOMMU and bind 1060 to vfio-pci on bastion

Add to `bastion/configuration.nix` (or a new `bastion/vfio.nix`):

```nix
# Enable IOMMU — substitute amd_iommu=on if bastion has an AMD CPU
boot.kernelParams = [
  "intel_iommu=on"
  "iommu=pt"                          # passthrough mode: best performance
  "vfio-pci.ids=10de:1c02,10de:10f1" # GTX 1060 GPU + audio — verify IDs
];

boot.kernelModules = [ "vfio_pci" "vfio_iommu_type1" "vfio" ];
boot.initrd.kernelModules = [ "vfio_pci" "vfio_iommu_type1" "vfio" ];

# Prevent the Nvidia driver from claiming the 1060 before vfio-pci does
boot.blacklistedKernelModules = [ "nvidia" "nouveau" ];
```

`iommu=pt` (passthrough) skips IOMMU translation for devices not under VFIO,
which avoids DMA performance overhead on the host's own devices.

After rebuilding and rebooting, verify:
```bash
lspci -ks <1060-pci-addr>   # should show "Kernel driver in use: vfio-pci"
ls /dev/vfio/               # should show the 1060's IOMMU group number
```

## Step 2 — Pass the device to the jellyfin microVM

microvm.nix exposes PCI passthrough via `microvm.devices`. Determine the group
number from `/dev/vfio/` then add to `bastion/hosts/t2/jellyfin.nix`:

```nix
microvm = {
  hypervisor = "cloud-hypervisor";   # explicit — required for VFIO

  devices = [{
    bus = "pci";
    path = "0000:XX:XX.X"; # substitute the actual PCI address of the 1060
  }];

  # The microvm process needs access to the VFIO group device node
  # cloud-hypervisor picks this up automatically via the PCI address,
  # but the group device must be accessible to the microvm user.
};
```

> **Note:** Verify the exact `microvm.devices` API against the current
> microvm.nix version — this option has changed between releases. Check
> `nix eval .#nixosConfigurations.jellyfin.options.microvm.devices` or read
> the upstream options docs.

Also ensure the microvm service user has access to `/dev/vfio/<group>`:
```nix
services.udev.extraRules = ''
  SUBSYSTEM=="vfio", GROUP="kvm", MODE="0660"
'';
```

## Step 3 — Guest-side Nvidia driver

The microVM needs the Nvidia driver to expose `/dev/nvidia*` inside the VM.
The kernel version in the guest must match the driver version on the host
(or at least be compatible — vfio-pci doesn't care, but the guest driver does).

```nix
# In jellyfin.nix or a new bastion/hosts/t2/jellyfin-gpu.nix
hardware.nvidia = {
  open = false;          # 1060 is Maxwell/Pascal — open module not supported
  modesetting.enable = false; # headless, no display in VM
  package = config.boot.kernelPackages.nvidiaPackages.stable;
};

hardware.graphics.enable = true;

# Load nvidia driver (not nouveau — 1060 is passed through, not emulated)
boot.blacklistedKernelModules = [ "nouveau" ];
boot.kernelModules = [ "nvidia" "nvidia_uvm" "nvidia_drm" ];
```

After boot, verify inside the VM:
```bash
nvidia-smi   # should show the GTX 1060
ls /dev/nvidia*  # nvidia0, nvidiactl, nvidia-uvm
```

## Step 4 — Expose GPU to the Jellyfin container

The Podman container needs the GPU device nodes passed through. Update the
container definition in `jellyfin.nix`:

```nix
virtualisation.oci-containers.containers.jellyfin = {
  # ... existing config ...
  extraOptions = [
    # existing healthcheck options ...

    # GPU device passthrough
    "--device=/dev/nvidia0"
    "--device=/dev/nvidiactl"
    "--device=/dev/nvidia-uvm"
    "--device=/dev/nvidia-uvm-tools"

    # Nvidia container runtime hook (required for NVENC inside container)
    "--runtime=nvidia"
  ] ++ # ... existing optionals ...;

  environment = {
    # ... existing env ...
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  };
};
```

This requires the `nvidia-container-toolkit` to be available to Podman.
On NixOS:
```nix
hardware.nvidia-container-toolkit.enable = true;
```

## Step 5 — Enable hardware transcoding in Jellyfin

In the Jellyfin web UI:
- Dashboard → Playback → Transcoding
- Hardware acceleration: **NVENC**
- Enable: H.264, H.265/HEVC, VP9 (1060 supports all three)
- Enable tone mapping if HDR content is in the library

The GTX 1060 supports:
- NVENC: H.264, H.265 encode
- NVDEC: H.264, H.265, VP9, MPEG-2, VC-1 decode
- Does NOT support AV1 (Pascal architecture limitation)

## Risks and gotchas

- **IOMMU group isolation** — most important prereq. If the 1060 is in a group
  with other devices, those devices must also be passed through (or the slot
  changed). Check this before writing any config.
- **Driver version matching** — guest Nvidia driver version must support the
  1060. The `stable` package in nixpkgs tracks the latest stable branch which
  supports Pascal (GTX 10xx) indefinitely.
- **Exclusive access** — once the 1060 is bound to vfio-pci, the host cannot
  use it (no CUDA, no host Nvidia driver). For bastion this is fine — the 1060
  has no host use case.
- **VM restart required for GPU changes** — unlike virtiofsd shares, PCI
  passthrough cannot be hot-added/removed from a running VM.
- **microvm.nix VFIO API** — verify the exact option name and format against
  the version pinned in `flake.nix`. The API has changed across releases.
- **jellyfin container still on linuxserver image** — the linuxserver/jellyfin
  image supports NVENC but requires `--runtime=nvidia` and the toolkit. If this
  proves difficult, switching to the official `jellyfin/jellyfin` image is an
  option (it also supports NVENC).

## vCPU reduction after GPU passthrough

Once hardware transcoding is working, the jellyfin VM's vCPU count can be
significantly reduced from 20. Hardware NVENC offloads the transcoding entirely;
the CPU is only needed for container overhead, NFS I/O, and the Jellyfin server
process itself. 4–6 vCPUs is likely sufficient post-passthrough.
