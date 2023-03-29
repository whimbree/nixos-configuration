{ pkgs, config, lib, ... }: {
  services.cockpit = {
    enable = true;
    port = 9090;
    settings = {
      WebService = {
        Origins = "https://cockpit-bastion.local.bspwr.com wss://cockpit-bastion.local.bspwr.com";
        ProtocolHeader = "X-Forwarded-Proto";
        AllowUnencrypted = "true";
      };
    };
  };

  # allow the cockpit TCP port through the firewall
  networking.firewall.allowedTCPPorts = [ 9090 ];
}
