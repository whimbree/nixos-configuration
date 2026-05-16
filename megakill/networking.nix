{ lib, ... }: {

  networking.networkmanager.enable = true;
  networking.useNetworkd = true;
  systemd.network.enable = true;

  # wait-online blocks boot until every managed interface is up, which is
  # irrelevant on a desktop — NetworkManager handles connectivity.
  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;

  networking.nameservers = [
    "1.1.1.1#one.one.one.one"
    "1.0.0.1#one.one.one.one"
  ];

  # systemd-resolved handles DNS with DNSSEC and DNS-over-TLS.
  # Domains = "~." makes resolved the authoritative resolver for all domains
  # (catch-all), so queries don't fall through to the stub resolver.
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = true;
      Domains = [ "~." ];
      FallbackDNS = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
      DNSOverTLS = true;
    };
  };

  networking.firewall.enable = true;
}
