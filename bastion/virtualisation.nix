{ pkgs, ... }: {

  virtualisation = {
    # podman = {
    #   # enable podman
    #   enable = true;
    #   # docker compatibility
    #   dockerSocket.enable = true;
    #   # create a `docker` alias for podman, to use it as a drop-in replacement
    #   dockerCompat = true;
    #   # required for containers under podman-compose to be able to talk to each other.
    #   defaultNetwork.dnsname.enable = true;
    #   # ZFS support
    #   extraPackages = [ pkgs.zfs ];
    # };
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
