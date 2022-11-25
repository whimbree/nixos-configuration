{ pkgs, ... }: {
  virtualisation = {
    # enable docker
    docker.enable = true;
    # enable libvirt
    libvirtd.enable = true;
    # enable LXD
    lxd.enable = true;
  };

  # virt-manager
  programs.dconf.enable = true;
  environment.systemPackages = with pkgs; [ virt-manager docker-compose ];

  # allow LXD websocket
  networking.firewall.allowedTCPPorts = [ 8443 ];

  # needed for LXD VMs
  boot.kernelModules = [ "vhost_vsock" ];

  # add groups
  users.users.bree.extraGroups = [ "docker" "qemu-libvirtd" "libvirtd" "lxd" ];
}
