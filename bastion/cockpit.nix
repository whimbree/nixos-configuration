{ pkgs, config, lib, ... }:
let
  nur-no-pkgs = import (builtins.fetchTarball
    "https://github.com/nix-community/NUR/archive/master.tar.gz") { };
in {

  imports = [ nur-no-pkgs.repos.dukzcry.modules.cockpit ];

  services.cockpit = {
    enable = true;
    port = 9090;
  };

  # allow the cockpit TCP port through the firewall
  networking.firewall.allowedTCPPorts = [ 9090 ];
}
