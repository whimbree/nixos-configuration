{ lib, pkgs, mkVMNetworking, ... }:
let
  # Import VM registry to get our config
  vmRegistry = import ../../vm-registry.nix;
  vmConfig = vmRegistry.vms.gateway;

  # Generate networking from registry data
  networking = mkVMNetworking { 
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };
in {
  microvm = {
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;
  };

  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # ACME for wildcard certificates only
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "whimbree@pm.me";
      dnsProvider = "porkbun";
      credentialsFile = "/var/lib/acme/porkbun-credentials";
    };

    # Generate wildcard certificate for your domain
    certs."bspwr.com" = {
      domain = "*.bspwr.com";
      extraDomainNames = [ "bspwr.com" ]; # Include bare domain too
      dnsProvider = "porkbun";
      credentialsFile = "/var/lib/acme/porkbun-credentials";
      group = "nginx";
    };
  };

  # Nginx configuration using wildcard cert
  services.nginx = {
    enable = true;

    # Explicitly set user (fixes ACME ownership detection)
    user = "nginx";
    group = "nginx";

    # Default SSL configuration for all vhosts
    sslCiphers =
      "ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384";
    sslProtocols = "TLSv1.2 TLSv1.3";

    virtualHosts = {
      # All subdomains use the same wildcard cert
      "deluge.bspwr.com" = {
        useACMEHost = "bspwr.com"; # Use wildcard cert
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.1.1:8096";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      # Add more services here - all using the same wildcard cert
    };
  };

  # Persistent storage for ACME certificates via microvm volume
  microvm.volumes = [{
    image = "acme-certs.img";
    mountPoint = "/var/lib/acme";
    size = 1024; # 1GB should be plenty for certificates
    fsType = "ext4";
    autoCreate = true;
  }];

  # Override firewall to allow HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
