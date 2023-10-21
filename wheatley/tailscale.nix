{ config, pkgs, ... }: {
  # enable tailscale
  services.tailscale = { enable = true; };

  networking.firewall = {
    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ 41641 ];
    # allow Tailscale exit nodes to work
    checkReversePath = "loose";
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
  };

  # disable SSH access through the firewall, only way in will be through tailscale
  services.openssh.openFirewall = false;

  # make the tailscale binary available to all users
  environment.systemPackages = [ pkgs.tailscale ];

  # needed for tailscale exit node
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
}