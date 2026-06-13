# Jellyfin GPU Passthrough — Debug Handoff

**Date:** 2026-05-25  
**Transcript:** [GPU passthrough + NVENC debugging](e7b1bb3b-a0aa-4cc0-b7d0-47fb0b0583b2)

## Goal

Enable NVENC/NVDEC hardware transcoding in the `jellyfin` microvm on `bastion` using a
GTX 1660 Ti (Turing TU116) passed through via VFIO.

## Architecture

- **Host:** `bastion` (AMD CPU, `amd_iommu=on`)
- **Guest:** `jellyfin` microvm (`microvm.nix`, **QEMU** — switched from cloud-hypervisor due to BAR truncation)
- **GPU:** GTX 1660 Ti — IOMMU Group 18, PCI `0000:2c:00.0` (appears as `00:0c.0` inside VM)
- **Container:** `lscr.io/linuxserver/jellyfin:nightly` via Podman
- **GPU exposure:** CDI (`hardware.nvidia-container-toolkit`), `--device=nvidia.com/gpu=all`

## What Has Been Done (all committed, all deployed)

### Host — `bastion/vfio.nix`
- Binds all four IOMMU Group 18 functions to `vfio-pci`:
  - `10de:2182` — TU116 GPU
  - `10de:1aeb` — TU116 HDMI audio
  - `10de:1aec` — TU116 USB 3.1
  - `10de:1aed` — TU116 USB-C UCSI
- `ignoreMSRs = true` (suppresses NVIDIA power-management MSR noise)
- Module at `modules/vfio.nix` (shared with megakill)

### Guest — `bastion/hosts/t2/jellyfin.nix`
- `microvm.devices = [{ bus = "pci"; path = "0000:2c:00.0"; }]`
- `nixpkgs.config.allowUnfree = true`
- `hardware.enableRedistributableFirmware = lib.mkForce true`
- `hardware.graphics.enable = true`
- `services.xserver.videoDrivers = [ "nvidia" ]` (satisfies nvidia-container-toolkit assertion)
- `hardware.nvidia.modesetting.enable = true`
- `hardware.nvidia.open = false` (proprietary module — see GSP section below)
- `hardware.nvidia.nvidiaPersistenced = true` (keeps GPU at P0)
- `hardware.nvidia.powerManagement.enable = false`
- `boot.extraModprobeConfig = "options nvidia NVreg_EnableGpuFirmware=0"` (disable GSP)
- `hardware.nvidia-container-toolkit.enable = true`
- Container `extraOptions`: `--device=nvidia.com/gpu=all`, `--group-add=video`
- Container env: `NVIDIA_VISIBLE_DEVICES=all`, `NVIDIA_DRIVER_CAPABILITIES=all`
- `systemd.services."podman-jellyfin"` depends on `nvidia-persistenced.service`
- Temporary debug packages added (strace, python3, pciutils, lsof, nvtop)

## Bugs Fixed Along the Way

| Bug | Fix |
|-----|-----|
| `abc` user got `Insufficient Permissions` from NVML | `--group-add=video` — `/dev/nvidia*` are `root:video 0660` |
| Redundant manual CDI symlink | Removed — NixOS module auto-configures Podman's `cdi_spec_dirs` |
| `build.nix` not finding `bastion/vfio.nix` | `git add bastion/vfio.nix` — file wasn't tracked |
| `nvidia-container-toolkit` assertion failure | Added `services.xserver.videoDrivers = ["nvidia"]` |
| `nvidia-smi` hanging after transcode attempt | `nvidiaPersistenced = true` — P8→P0 deadlock fixed |
| ffmpeg hung forever on CUDA context init (all threads on `futex_do_wait`) | `open = false` + `NVreg_EnableGpuFirmware=0` — GSP RPC deadlock in VFIO VM |

## Root Cause Found — Cloud-Hypervisor BAR1 Truncation

**Diagnosis (2026-05-25):**

`lspci -vvv -s 00:0c.0` inside the guest revealed:

```
Region 1: Memory at 7ffe0000000 (64-bit, prefetchable) [size=256M]   ← should be 6144M
LnkSta: Speed 2.5GT/s (downgraded), Width x8 (downgraded)            ← should be 8GT/s x16
```

The GTX 1660 Ti has 6 GB of VRAM. Cloud-hypervisor only maps the first **256 MB** of BAR1
into the guest. The NVIDIA driver sets up CUDA contexts and DMA buffers beyond that 256 MB
boundary → hits unmapped guest memory → GPU engine exception (Xid 32) →
`CUDA_ERROR_LAUNCH_FAILED`.

The `--privileged` container run got further into CUDA init (past the nvidia-caps check) and
then **hung** instead of fast-failing — CUDA was spinning trying to access frame buffer memory
past the truncated boundary.

**Fix:** switch the `jellyfin` microvm from cloud-hypervisor to QEMU. QEMU's Q35 machine
has a proper 64-bit MMIO window and correctly maps the full 6 GB BAR1. Change committed
to `jellyfin.nix`; see below.

---

## Previous Issue (Resolved) — `CUDA_ERROR_LAUNCH_FAILED` + Xid 32

**Symptom:** After switching to the proprietary module + disabling GSP, ffmpeg no longer hangs
forever but now fails fast (~0.2s) with:

```
[h264_nvenc] dl_fn->cuda_dl->cuCtxCreate(...) failed -> CUDA_ERROR_LAUNCH_FAILED: unspecified launch failure
[h264_nvenc] No capable devices found
```

Simultaneously, dmesg shows:
```
NVRM: Xid (PCI:0000:00:0c): 32, pid=1951, name=vf#0:0, channel 0x00000013 intr0 00040000
NVRM: Xid (PCI:0000:00:0c): 32, pid=1951, name=vf#0:0, channel 0x00000013 intr0 00040000
```

**Xid 32** is a GPU engine exception — the GPU received an invalid command during CUDA context
initialisation. This is the kernel-side error behind `CUDA_ERROR_LAUNCH_FAILED`.

### Confirmed facts

| Item | Status |
|------|--------|
| `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm` in CDI spec | ✓ |
| `/dev/nvidia-caps/nvidia-cap1` (`cr--------`) exists on host | ✓ |
| `/dev/nvidia-caps/nvidia-cap2` (`cr--r--r--`) exists on host | ✓ |
| nvidia-caps included in CDI spec | ✗ — `grep caps` returns 0 even after regenerating spec |
| Proprietary module loaded | ✓ — `/proc/driver/nvidia/version` confirmed |
| `nvidia-persistenced` healthy | ✓ — `Persistence-M: On` in nvidia-smi |
| `NVreg_EnableGpuFirmware=0` effective | **Unknown** — not yet checked |

### What has NOT been tried yet

1. **Verify GSP is actually disabled:**
   ```bash
   cat /proc/driver/nvidia/params | grep -i firmware
   ```
   If `EnableGpuFirmware` is still 1, the `NVreg_EnableGpuFirmware=0` setting isn't being
   applied (possible if the option is ignored with the proprietary module on some versions).

2. **Test with `--privileged`** to rule out container security restrictions entirely:
   ```bash
   sudo podman run --rm --privileged \
     docker.io/linuxserver/ffmpeg \
     -f lavfi -i testsrc=duration=5:size=1920x1080:rate=30 \
     -c:v h264_nvenc -preset p1 -f null /dev/null
   ```
   If this works → CDI/permissions issue (nvidia-caps not injected).
   If it still fails with Xid 32 → deeper GPU/hypervisor problem.

3. **Inspect full CDI spec device list** (jq is already installed):
   ```bash
   jq '.devices[].containerEdits.deviceNodes[].path' \
     /run/cdi/nvidia-container-toolkit.json
   ```

4. **Explicitly pass nvidia-caps into the test container:**
   ```bash
   sudo podman run --rm \
     --device=nvidia.com/gpu=all \
     --device=/dev/nvidia-caps/nvidia-cap1 \
     --device=/dev/nvidia-caps/nvidia-cap2 \
     --security-opt=label=disable \
     docker.io/linuxserver/ffmpeg \
     -f lavfi -i testsrc=duration=5:size=1920x1080:rate=30 \
     -c:v h264_nvenc -preset p1 -f null /dev/null
   ```

5. **strace the CUDA init** (strace is now installed):
   Run the ffmpeg command, then in another shell:
   ```bash
   # find the PID
   ps aux | grep ffmpeg
   sudo strace -p <PID> -f -e trace=ioctl,openat,futex 2>&1 | head -60
   ```

6. **Check PCIe BAR mapping** (pciutils now installed):
   ```bash
   sudo lspci -vvv -s 00:0c.0 | head -40
   ```
   Look for BAR sizes and whether they're properly mapped. Xid 32 can be caused by
   broken BAR access in cloud-hypervisor's PCIe emulation.

7. **Try `iommu=pt` on the bastion host** kernel params. AMD VFIO sometimes needs
   passthrough mode to avoid IOMMU translation overhead that confuses CUDA DMA.
   In `bastion/configuration.nix` or `bastion/vfio.nix`:
   ```nix
   boot.kernelParams = [ ... "iommu=pt" ];
   ```

## Hypotheses (resolved)

1. ~~**nvidia-caps not injected into container**~~ — Ruled out. `--privileged --device=nvidia.com/gpu=all`
   still failed (hung), confirming the problem is below the container layer.

2. ~~**No virtual IOMMU (vIOMMU) in cloud-hypervisor guest**~~ — Irrelevant; root cause identified as BAR truncation.

3. **✓ CONFIRMED: Xid 32 is the actual root cause (BAR mapping broken in cloud-hypervisor)**
   — `lspci` inside the guest shows BAR1 mapped at `[size=256M]` instead of `[size=6144M]`.
   Cloud-hypervisor truncates the 6 GB VRAM BAR. CUDA writes beyond 256 MB → Xid 32.
   *Fix: switch to QEMU (`microvm.hypervisor = lib.mkForce "qemu"`).*

4. ~~**GSP still running**~~ — Ruled out. `/proc/driver/nvidia/params` confirmed `EnableGpuFirmware: 0`.

## Key Files

| File | Purpose |
|------|---------|
| `bastion/hosts/t2/jellyfin.nix` | Main VM config — GPU, NVIDIA driver, Podman container |
| `bastion/vfio.nix` | Host-side VFIO binding for all four GPU functions |
| `bastion/configuration.nix` | Imports `./vfio.nix` |
| `modules/vfio.nix` | Shared VFIO NixOS module (used by bastion and megakill) |
| `bastion/modules/microvm-defaults.nix` | Shared microvm defaults (cloud-hypervisor, base packages) |

## Deployment

**Do not use `nixos-rebuild switch` targeting the microvm — this will nuke the homelab.**

To update `jellyfin` after config changes, **on `bastion`**:
```bash
sudo microvm -uR jellyfin
```

## Useful Commands

```bash
# Check GPU driver params (including firmware/GSP setting)
cat /proc/driver/nvidia/params | grep -i firmware

# Check all devices in CDI spec
jq '.devices[].containerEdits.deviceNodes[].path' /run/cdi/nvidia-container-toolkit.json

# Regenerate CDI spec
sudo systemctl restart nvidia-container-toolkit-cdi-generator.service

# Check for GPU errors in kernel log
sudo dmesg | grep -iE "nvidia|nvrm|xid|vfio|iommu" | tail -30

# Test NVENC in container (now that debug packages are deployed)
sudo podman run --rm --device=nvidia.com/gpu=all --security-opt=label=disable \
  docker.io/linuxserver/ffmpeg \
  -f lavfi -i testsrc=duration=5:size=1920x1080:rate=30 \
  -c:v h264_nvenc -preset p1 -f null /dev/null

# GPU real-time monitoring
nvtop

# PCIe config space for GPU (pciutils now installed)
sudo lspci -vvv -s 00:0c.0
```

## GPU Capabilities Reference (GTX 1660 Ti / TU116)

| Codec | Decode | Encode |
|-------|--------|--------|
| H.264 8-bit | ✓ | ✓ |
| HEVC 8-bit | ✓ | ✓ |
| HEVC 10-bit | ✓ (decode only) | ✗ (Pascal+ only) |
| VP8/VP9 | ✓ decode | ✗ encode |
| AV1 | ✗ | ✗ (Ampere/Ada only) |

Max concurrent NVENC sessions: no hard cap on R550+ drivers (previous 3-session limit removed).  
Practical 4K limit: ~2–3 simultaneous streams (VRAM bound at 6 GB).
