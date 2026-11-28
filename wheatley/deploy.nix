{ pkgs, lib, ... }:
# Lets bastion push wheatley's system with deploy-rs (see deploy.nodes in
# flake.nix and bastion/deploy-wheatley.nix). The deploy account is
# root-equivalent by necessity: activating a system needs root. What limits
# it is who can log in: only bastion's deploy key, only from bastion's
# Tailscale IPv4 address, with no forwarding or terminal.
let
  # Private half: bastion:/persist/var/lib/wheatley-deploy/id_ed25519.
  bastionDeployKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAF9rQHGwpvT1mrZMyKJjCDY+uGYaeAbpa71xXlA3iao deploy@bastion";
  bastionTailscaleIp = "100.64.0.4";
in {
  assertions = [{
    assertion = lib.hasPrefix "ssh-ed25519 " bastionDeployKey;
    message = "wheatley/deploy.nix: set bastionDeployKey to bastion's deploy public key";
  }];

  users.users.deploy = {
    isSystemUser = true;
    group = "deploy";
    home = "/var/empty";
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      ''restrict,from="${bastionTailscaleIp}" ${bastionDeployKey}''
    ];
  };
  users.groups.deploy = { };

  security.sudo.extraRules = [{
    users = [ "deploy" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  # Accept the unsigned store paths bastion builds.
  nix.settings.trusted-users = [ "deploy" ];
}
