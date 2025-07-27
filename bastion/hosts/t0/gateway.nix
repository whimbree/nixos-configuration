{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

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

  networking.hostName = vmConfig.hostname;
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
      # Alternative: HTML response with more styling
      "deluge.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          extraConfig = ''
            return 200 '<!DOCTYPE html>
            <html>
            <head><title>Hello World</title></head>
            <body>
              <h1>Hello World!</h1>
              <p>This is served from ${vmConfig.hostname}</p>
              <p>SSL terminated by nginx</p>
            </body>
            </html>';
            add_header Content-Type text/html;
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

  microvm.shares = [{
    source = "/services/traefik/secrets";
    mountPoint = "/host-secrets";
    tag = "secrets";
    proto = "virtiofs";
    securityModel = "none"; # For access to secret files
  }];

  systemd.services.create-porkbun-credentials = {
    description = "Create Porkbun credentials file from secrets";
    before = [ "acme-bspwr.com.service" "nginx.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Wait for microvm shares to be available
      while [ ! -d /host-secrets ]; do
        echo "Waiting for host secrets to be mounted..."
        sleep 2
      done

      mkdir -p /var/lib/acme
      {
        echo "PORKBUN_API_KEY=$(cat /host-secrets/porkbun-api-key)"
        echo "PORKBUN_SECRET_API_KEY=$(cat /host-secrets/porkbun-secret-api-key)"
      } > /var/lib/acme/porkbun-credentials

      chown root:nginx /var/lib/acme/porkbun-credentials
      chmod 640 /var/lib/acme/porkbun-credentials

      echo "Porkbun credentials file created successfully"
    '';
  };

  # Override firewall to allow HTTP/HTTPS
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
}
