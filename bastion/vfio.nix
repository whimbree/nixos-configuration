{ ... }: {
  imports = [ ../modules/vfio.nix ];

  virtualisation.vfio = {
    enable = true;
    IOMMUType = "amd";

    # All four functions of the GTX 1660 Ti live in IOMMU Group 18 alone.
    # Every function in a group must be claimed by vfio-pci before any can be
    # passed through, so bind all four here even though only 2c:00.0 (the GPU)
    # is forwarded to the jellyfin-new microvm.
    #
    # lspci -nn output (bus 2c:00.*):
    #   10de:2182  TU116 [GeForce GTX 1660 Ti]
    #   10de:1aeb  TU116 High Definition Audio Controller
    #   10de:1aec  TU116 USB 3.1 Host Controller
    #   10de:1aed  TU116 USB Type-C UCSI Controller
    devices = [
      "10de:2182"
      "10de:1aeb"
      "10de:1aec"
      "10de:1aed"
    ];

    # Suppress VM exits for unhandled MSR reads/writes; avoids noise from
    # the NVIDIA driver probing power-management MSRs the host doesn't expose.
    ignoreMSRs = true;
  };
}
