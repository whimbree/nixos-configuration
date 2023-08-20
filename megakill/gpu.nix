{ config, pkgs, lib, ... }: {

  # Allow AMD driver to start in initrd stage
  # If vfio-pci is bound to a secondary GPU (eg: Nvidia)
  # Then this is required or the framebuffer will not display!
  boot.initrd.kernelModules = [ "amdgpu" ];

  # AMD uses the modesetting driver
  services.xserver.exportConfiguration = true;
  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];

  # AMD OpenCL
  hardware.opengl.extraPackages = with pkgs; [
    rocm-opencl-icd
    rocm-opencl-runtime
  ];

  # Enable opengl/vulkan
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  hardware.nvidia = {
    # Modesetting is needed for most Wayland compositors
    # We have it disabled since the Nvidia card is not primary GPU
    # And it breaks graphics to have two GPUs with modesetting on both
    modesetting.enable = false;
    # Use the open source version of the kernel module
    # Only available on driver 515.43.04+
    open = false;
    # Enable the nvidia settings menu
    nvidiaSettings = true;
    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

}
