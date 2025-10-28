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

    appendHttpConfig = ''
      proxy_temp_path /var/cache/nginx/proxy_temp;
      proxy_cache_path /var/cache/nginx/cache levels=1:2 keys_zone=cache:10m max_size=4g inactive=60m;
    '';

    virtualHosts = {
      # All subdomains use the same wildcard cert
      "deluge.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.1.1:8112"; # Deluge web UI port
          proxyWebsockets = true; # Important for deluge web UI
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Deluge-specific headers
            proxy_set_header X-Deluge-Base "/";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "prowlarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.1.1:9696"; # Prowlarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "sonarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.1.1:8989"; # Sonarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "radarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.1.1:7878"; # Radarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "jellyfin.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.2.1:8096"; # Jellyfin web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "immich.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.3.1:2283"; # Immich web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      # Nextcloud services
      "nextcloud.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."= /.well-known/carddav" = {
          return = "301 $scheme://$host/remote.php/dav";
        };
        locations."= /.well-known/caldav" = {
          return = "301 $scheme://$host/remote.php/dav";
        };
        locations."/push/" = {
          proxyPass = "http://10.0.3.2:7867/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for push notifications
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
        locations."/" = {
          proxyPass = "http://10.0.3.2:80";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Nextcloud-specific headers
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $host;

            # Increase timeouts and buffer sizes for large file operations
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
            proxy_buffering off;
            proxy_request_buffering off;
            client_max_body_size 10G;

            # Required for Nextcloud
            proxy_redirect off;
          '';
        };
      };

      "collabora.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.3.2:9980";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Collabora-specific settings
            proxy_buffering off;
            proxy_request_buffering off;

            # Increase timeouts for document editing
            proxy_connect_timeout 300s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
          '';
        };
      };

      "photoprism.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false; # TODO remove once traefik is gone
        locations."/" = {
          proxyPass = "http://10.0.3.3:2342"; # Photoprism web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close"; # TODO remove once traefik is gone

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "syncthing.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false;
        locations."/" = {
          proxyPass = "http://10.0.3.4:8384";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "blog.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false;
        locations."/" = {
          proxyPass = "http://10.0.1.3:80";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "downloads.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false;
        locations."/" = {
          proxyPass = "http://10.0.2.2:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "media.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false;
        locations."/" = {
          proxyPass = "http://10.0.2.2:8081";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "files-webdav.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false;
        locations."/" = {
          proxyPass = "http://10.0.3.5:8090";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "files.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        http2 = false;
        locations."/" = {
          proxyPass = "http://10.0.3.5:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "close";

            # Increase timeouts for large file operations
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };

      "alex-duplicati.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.6:8080";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Large file support for backups
            client_max_body_size 10G;

            # Long timeouts for backup uploads
            proxy_connect_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_read_timeout 3600s;

            # Disable buffering for large backups
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };

      # Add more services here - all using the same wildcard cert
    };
  };

  # Persistent storage for ACME certificates via microvm volume
  microvm.volumes = [
    {
      image = "acme-certs.img";
      mountPoint = "/var/lib/acme";
      size = 1024; # 1GB should be plenty for certificates
      fsType = "ext4";
      autoCreate = true;
    }
    {
      image = "nginx-cache.img"; # Add this
      mountPoint = "/var/cache/nginx";
      size = 1024 * 10; # 10GB for proxy temp files
      fsType = "ext4";
      autoCreate = true;
    }
  ];

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
