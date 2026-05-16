{ config, pkgs, machineConfig, ... }:

let
  # Unbind the RTX 3090 from the Nvidia driver and hand it to vfio-pci at
  # runtime, making it available for VM passthrough. AMD remains the display
  # GPU throughout. Run before starting the VM.
  # Requires: no processes actively using the Nvidia card (CUDA, etc.).
  nvidia-detach = pkgs.writeShellScriptBin "nvidia-detach" ''
    set -euo pipefail

    GPU_ID="${machineConfig.gpu.nvidia.pciId}"
    AUDIO_ID="${machineConfig.gpu.nvidia.audioPciId}"

    # Find PCI addresses dynamically by vendor:device ID
    GPU_ADDR=$(lspci -D -d "$GPU_ID" | awk '{print $1}')
    AUDIO_ADDR=$(lspci -D -d "$AUDIO_ID" | awk '{print $1}')

    if [ -z "$GPU_ADDR" ]; then
      echo "ERROR: ${machineConfig.gpu.nvidia.name} not found (already bound to vfio-pci?)"
      exit 1
    fi

    echo "${machineConfig.gpu.nvidia.name} GPU:   $GPU_ADDR"
    echo "${machineConfig.gpu.nvidia.name} Audio: $AUDIO_ADDR"

    ${pkgs.kmod}/bin/modprobe vfio-pci

    for ADDR in $GPU_ADDR $AUDIO_ADDR; do
      DRIVER=$(readlink /sys/bus/pci/devices/$ADDR/driver 2>/dev/null | xargs basename 2>/dev/null || true)
      if [ -n "$DRIVER" ] && [ "$DRIVER" != "vfio-pci" ]; then
        echo "Unbinding $ADDR from $DRIVER..."
        echo "$ADDR" > /sys/bus/pci/drivers/$DRIVER/unbind
      fi
      echo "Binding $ADDR to vfio-pci..."
      echo "$ADDR" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || \
        echo "vfio-pci" > /sys/bus/pci/devices/$ADDR/driver_override && \
        echo "$ADDR" > /sys/bus/pci/drivers/vfio-pci/bind
    done

    echo "${machineConfig.gpu.nvidia.name} is now bound to vfio-pci and ready for passthrough."
  '';

  # Reclaim the RTX 3090 from vfio-pci and re-bind it to the Nvidia driver.
  # Run after the VM has fully shut down.
  nvidia-attach = pkgs.writeShellScriptBin "nvidia-attach" ''
    set -euo pipefail

    GPU_ID="${machineConfig.gpu.nvidia.pciId}"
    AUDIO_ID="${machineConfig.gpu.nvidia.audioPciId}"

    GPU_ADDR=$(lspci -D -d "$GPU_ID" | awk '{print $1}')
    AUDIO_ADDR=$(lspci -D -d "$AUDIO_ID" | awk '{print $1}')

    if [ -z "$GPU_ADDR" ]; then
      echo "ERROR: ${machineConfig.gpu.nvidia.name} not found on PCI bus."
      exit 1
    fi

    echo "${machineConfig.gpu.nvidia.name} GPU:   $GPU_ADDR"
    echo "${machineConfig.gpu.nvidia.name} Audio: $AUDIO_ADDR"

    for ADDR in $GPU_ADDR $AUDIO_ADDR; do
      DRIVER=$(readlink /sys/bus/pci/devices/$ADDR/driver 2>/dev/null | xargs basename 2>/dev/null || true)
      if [ "$DRIVER" = "vfio-pci" ]; then
        echo "Unbinding $ADDR from vfio-pci..."
        echo "$ADDR" > /sys/bus/pci/drivers/vfio-pci/unbind
      fi
      # Clear driver_override so the kernel re-probes normally
      echo "" > /sys/bus/pci/devices/$ADDR/driver_override
    done

    echo "Triggering re-probe for Nvidia driver..."
    ${pkgs.kmod}/bin/modprobe nvidia
    echo "$GPU_ADDR" > /sys/bus/pci/drivers/nvidia/bind 2>/dev/null || \
      echo "$GPU_ADDR" > /sys/bus/pci/drivers_probe

    echo "${machineConfig.gpu.nvidia.name} is now bound to the Nvidia driver."
  '';
in {

  # amdgpu must be loaded in the initrd stage. Without this, when the Nvidia
  # card is bound to vfio-pci (VFIO specialisation), there is no fallback
  # framebuffer driver and the display goes blank during boot.
  boot.initrd.kernelModules = [ "amdgpu" ];

  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # needed for 32-bit games / Wine / Steam
    extraPackages = with pkgs; [
      # ROCm OpenCL runtime — exposes the AMD GPU for GPU compute workloads.
      rocmPackages.clr.icd
      rocmPackages.clr
    ];
  };

  environment.systemPackages = [ nvidia-detach nvidia-attach ];

  hardware.nvidia = {
    # Modesetting is disabled on the Nvidia card because it is the secondary
    # GPU (AMD is primary). Enabling modesetting on both GPUs simultaneously
    # causes display corruption / failure to start the compositor.
    modesetting.enable = false;

    # Open-source Nvidia kernel module — NOT available for the RTX 3090 (Ada
    # generation and newer only). Must stay false for this card.
    open = false;

    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
