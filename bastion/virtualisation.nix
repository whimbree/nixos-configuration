{ pkgs, ... }: {

  # needed for arion
  environment.systemPackages = [
    pkgs.arion

    # Do install the docker CLI to talk to podman.
    # Not needed when virtualisation.docker.enable = true;
    pkgs.docker-client
  ];

  virtualisation = {
    podman = {
      # enable podman
      enable = true;
      # needed for arion
      dockerSocket.enable = true;
      # create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;
      # required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.dnsname.enable = true;
      # ZFS support
      extraPackages = [ pkgs.zfs ];
    };
    # enable libvirt
    libvirtd.enable = true;
    # enable LXD
    lxd.enable = true;
  };

  # add groups
  users.users.bree.extraGroups = [ "podman" "qemu-libvirtd" "libvirtd" "lxd" ];

  # set podman as the oci container backend
  virtualisation.oci-containers.backend = "podman";
  # virtualisation.oci-containers.containers = {
  #   container-name = {
  #     image = "container-image";
  #     autoStart = true;
  #     ports = [ "127.0.0.1:1234:1234" ];
  #   };
  # };
}
