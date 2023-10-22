{ config, pkgs, lib, ... }: {

  systemd.services.docker-create-network-socks-proxy = {
    enable = true;
    description = "Create socks-proxy docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-socks-proxy" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create socks-proxy || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."socks-proxy" = {
    autoStart = true;
    image = "ghcr.io/whimbree/socks5-server:latest";
    ports = [ "4242:4242" ];
    environment = { PROXY_PORT = "4242"; };
    dependsOn = [ "create-network-socks-proxy" ];
    extraOptions = [
      # networks
      "--network=socks-proxy"
    ];
  };

}
