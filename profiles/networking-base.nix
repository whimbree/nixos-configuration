{ lib, ... }: {
  networking.useNetworkd = true;
  systemd.network.enable = true;

  # wait-online stalls boot until every managed interface is up. Desktops don't
  # need it (NM handles connectivity) and servers don't benefit from it either.
  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;

  networking.nameservers = [
    "1.1.1.1#one.one.one.one"
    "1.0.0.1#one.one.one.one"
  ];

  # systemd-resolved with DNSSEC and DNS-over-TLS.
  # Domains = "~." makes resolved the catch-all resolver for every domain so
  # queries never fall through to the stub resolver.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = true;
      Domains = [ "~." ];
      FallbackDNS = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
      DNSOverTLS = true;
    };
  };

  # Prevent DHCP from registering the ISP's DNS server as a per-link resolver
  # with systemd-resolved. Without this, resolved registers the DHCP-provided
  # DNS (typically the router/ISP) as a per-link server alongside Cloudflare.
  # It then races both in parallel: the per-link server gets attempted with DoT
  # (since DNSOverTLS is global), fails TLS because home routers don't support
  # it, and resolved retries it repeatedly while the global Cloudflare DoT
  # server handles the query. The net effect is latency + log spam on every
  # lookup. Disabling UseDNS here stops DHCP from injecting anything into
  # resolved's server list; all DNS comes exclusively from services.resolved.
  # (systemd/systemd issue #18060, reported fixed in v249 for the plaintext
  # fallback bug, but the per-link racing behaviour persists independently.)
  systemd.network.networks."10-*".dhcpV4Config.UseDNS = false;
}
