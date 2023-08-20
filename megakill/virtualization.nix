{ pkgs, ... }: {

  imports = [ ./modules/vfio.nix ];

  virtualisation = {
    # enable podman
    podman = {
      enable = true;
      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;
      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
      extraPackages = [ pkgs.zfs ];
    };
    oci-containers.backend = "podman";
    # enable libvirt
    libvirtd.enable = true;
    # enable LXD
    lxd = {
      enable = true;
      zfsSupport = true;
      recommendedSysctlSettings = true;
    };
    lxc.lxcfs.enable = true;
    spiceUSBRedirection.enable = true;
  };

  specialisation."VFIO".configuration = {
    system.nixos.tags = [ "with-vfio" ];
    virtualisation.vfio = {
      enable = true;
      IOMMUType = "amd";
      devices = [
        "10de:2204" # RTX 3090 Graphics
        "10de:1aef" # RTX 3090 Audio
      ];
      blacklistNvidia = true;
      ignoreMSRs = true;
      disablePCIeASPM = true;
      disableEFIfb = false;
    };
  };

  # virt-manager
  programs.dconf.enable = true;
  environment.systemPackages = with pkgs; [
    virt-manager
    podman-compose
    util-linux
  ];

  # allow LXD websocket
  networking.firewall.allowedTCPPorts = [ 8443 ];

  # enable KVM, enable the capacity to launch vm with a virtual socket (network)
  boot.kernelModules = [ "kvm-amd" "vhost_vsock" ];

  # add groups
  users.users.bree.extraGroups = [ "docker" "qemu-libvirtd" "libvirtd" "lxd" ];
}
