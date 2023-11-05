{ pkgs, config, ... }: {

  imports = [
    ./modules/vfio.nix
    ./modules/libvirt.nix
    ./modules/virtualisation.nix
    ./modules/kvmfr-options.nix
  ];

  virtualisation = {
    # enable docker
    docker = {
      enable = true;
      autoPrune.enable = true;
      storageDriver = "overlay2";
      liveRestore = true;
      daemon.settings = {
        default-address-pools = [{
          base = "172.17.0.0/12";
          size = 20;
        }];
      };
    };
    oci-containers.backend = "docker";
    # enable LXD
    # lxd = {
    #   enable = true;
    #   zfsSupport = true;
    #   recommendedSysctlSettings = true;
    # };
    # lxc.lxcfs.enable = true;
    # enable libvirt
    libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm;
        ovmf = {
          enable = true;
          # https://github.com/NixOS/nixpkgs/issues/164064
          packages = [
            (pkgs.OVMF.override {
              secureBoot = true;
              csmSupport = false;
              httpSupport = true;
              tpmSupport = true;
            }).fd
          ];
        };
        swtpm.enable = true;
        runAsRoot = false;
      };
      clearEmulationCapabilities = false;
      deviceACL = [
        "/dev/ptmx"
        "/dev/kvm"
        "/dev/kvmfr0"
        "/dev/vfio/vfio"
        "/dev/vfio/30"
      ];
    };
    # KVM FrameRelay for Looking Glass
    kvmfr = {
      enable = true;
      shm = {
        enable = true;
        size = 128;
        user = "bree";
        group = "qemu-libvirtd";
        mode = "0666";
      };
    };
    # USB redirection in virtual machine
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
    docker-compose
    util-linux
  ];

  # allow LXD websocket
  # networking.firewall.allowedTCPPorts = [ 8443 ];

  # enable KVM, enable the capacity to launch vm with a virtual socket (network)
  boot.kernelModules = [ "kvm-amd" "vhost_vsock" ];

  # add groups
  users.users.bree.extraGroups =
    [ "kvm" "docker" "qemu-libvirtd" "libvirtd" "lxd" ];
}
