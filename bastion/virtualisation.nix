{ pkgs, ... }: {
  virtualisation = {
    # enable docker
    docker = {
      enable = true;
      storageDriver = "zfs";
    };
    # enable libvirt
    libvirtd.enable = true;
    # enable LXD
    lxd = {
      enable = true;
      zfsSupport = true;
      recommendedSysctlSettings=true;
    };
    lxc.lxcfs.enable = true;
  };

  # virt-manager
  programs.dconf.enable = true;
  environment.systemPackages = with pkgs; [ virt-manager docker-compose util-linux ];

  # allow LXD websocket
  networking.firewall.allowedTCPPorts = [ 8443 ];

  # enable KVM, enable the capacity to launch vm with a virtual socket (network)
  boot.kernelModules = [ "kvm-amd" "vhost_vsock" ];

  # add groups
  users.users.bree.extraGroups = [ "docker" "qemu-libvirtd" "libvirtd" "lxd" ];
}
