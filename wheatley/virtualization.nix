{ pkgs, ... }: {
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
      extraOptions = "--iptables=false --ip6tables=false";
    };
    oci-containers.backend = "docker";
  };

  environment.systemPackages = with pkgs; [ docker-compose util-linux ];

  # add docker group
  users.users.bree.extraGroups = [ "docker" ];
}
