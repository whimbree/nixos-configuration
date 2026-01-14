{ pkgs, ... }: {
  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    # enable docker
    # docker = {
    #   enable = true;
    #   autoPrune.enable = true;
    #   storageDriver = "overlay2";
    #   liveRestore = true;
    #   daemon.settings = {
    #     default-address-pools = [{
    #       base = "172.17.0.0/12";
    #       size = 20;
    #     }];
    #     ip = "127.0.0.1";
    #   };
    # };
    oci-containers.backend = "podman";
  };

  environment.systemPackages = with pkgs; [ util-linux ];
}
