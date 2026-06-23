{ config, pkgs, ... }: {
  # enable tailscale
  services.tailscale = { enable = true; };

  # Headscale (our control plane) runs on this same host behind nginx, so on a
  # cold boot tailscaled can come up before Headscale is serving, leaving the
  # node disconnected until a manual `tailscale up`. Run that command
  # automatically and keep retrying until Headscale answers; once it succeeds
  # once, tailscaled maintains the connection on its own. `tailscale up` is
  # idempotent, so this is a no-op when already connected.
  systemd.services.tailscale-autoconnect = {
    description = "Connect to Headscale (retry until reachable)";
    after = [
      "tailscaled.service"
      "headscale.service"
      "nginx.service"
      "network-online.target"
    ];
    wants = [ "tailscaled.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # The control plane may not be serving yet right after boot, and
      # `tailscale up` blocks indefinitely rather than failing -- so bound each
      # attempt with `timeout`: if it makes no progress within 20s, kill it and
      # retry. A healthy connect finishes in a few seconds; 20s only trips when
      # Headscale is unreachable. Retry for ~10 minutes; after one success
      # tailscaled keeps the connection alive across transient outages on its own.
      for _ in $(seq 1 60); do
        if ${pkgs.coreutils}/bin/timeout --kill-after=5s 20s \
            ${pkgs.tailscale}/bin/tailscale up \
              --advertise-exit-node \
              --login-server=https://headscale.whimsical.cloud; then
          echo "tailscale-autoconnect: connected to Headscale!" >&2
          ${pkgs.tailscale}/bin/tailscale status >&2 || true
          exit 0
        fi
        echo "tailscale-autoconnect: attempt timed out or failed, retrying..." >&2
        sleep 10
      done
      echo "tailscale-autoconnect: Headscale not reachable after retries" >&2
      exit 1
    '';
  };

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
