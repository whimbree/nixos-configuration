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
      
      # Security headers for all sites
      add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
      add_header X-Robots-Tag "noindex, nofollow" always;
      
      # Hide backend's X-Robots-Tag to avoid duplicates
      proxy_hide_header X-Robots-Tag;
    '';

    clientMaxBodySize = "100M"; # Reasonable file size limit
    commonHttpConfig = ''
      # Reasonable timeouts for typical web traffic
      proxy_connect_timeout 60s;
      proxy_send_timeout 300s;
      proxy_read_timeout 300s;
      client_body_timeout 60s;
      client_header_timeout 60s;
      send_timeout 300s;
      keepalive_timeout 65s;

      # Standard buffering settings (efficient for most content)
      client_body_buffer_size 128k;
      proxy_buffering on;           # ON for most traffic
      proxy_request_buffering on;   # ON for most traffic

      # Standard proxy buffer sizes
      proxy_buffer_size 4k;
      proxy_buffers 8 4k;
      proxy_busy_buffers_size 8k;
    '';

    virtualHosts = {
      # All subdomains use the same wildcard cert
      "deluge.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.1.1:8112"; # Deluge web UI port
          proxyWebsockets = true; # Important for deluge web UI
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Deluge-specific headers
            proxy_set_header X-Deluge-Base "/";
          '';
        };
      };

      "prowlarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.1.1:9696"; # Prowlarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "sonarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.1.1:8989"; # Sonarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "radarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.1.1:7878"; # Radarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "jellyfin.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.2.1:8096"; # Jellyfin web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "immich.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.1:2283"; # Immich web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Increase timeouts for large file operations
            proxy_send_timeout 3600s;
            proxy_read_timeout 3600s;
            client_body_timeout 3600s;
            send_timeout 3600s;

            # Set reasonable file size limit
            client_max_body_size 100G;

            # Optimize buffering for large file operations
            client_body_buffer_size 10M;
            proxy_buffering off;
            proxy_request_buffering off;

            # Increase proxy buffer sizes for large responses
            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;
          '';
        };
      };

      # Nextcloud services
      "nextcloud.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;

        locations."/push/" = {
          proxyPass = "http://10.0.3.2:7867";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
        locations."/" = {
          proxyPass = "http://10.0.3.2:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Increase timeouts for large file operations
            proxy_send_timeout 3600s;
            proxy_read_timeout 3600s;
            client_body_timeout 3600s;
            send_timeout 3600s;

            # Set reasonable file size limit
            client_max_body_size 100G;

            # Optimize buffering for large file operations
            client_body_buffer_size 10M;
            proxy_buffering off;
            proxy_request_buffering off;

            # Increase proxy buffer sizes for large responses
            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;
          '';
        };
      };

      "collabora.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.2:9980";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Collabora-specific settings
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };

      "photoprism.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.3:2342"; # Photoprism web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "syncthing.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.4:8384";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Increase timeouts for large file operations
            proxy_send_timeout 3600s;
            proxy_read_timeout 3600s;
            client_body_timeout 3600s;
            send_timeout 3600s;

            # Set reasonable file size limit
            client_max_body_size 100G;

            # Optimize buffering for large file operations
            client_body_buffer_size 10M;
            proxy_buffering off;
            proxy_request_buffering off;

            # Increase proxy buffer sizes for large responses
            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;
          '';
        };
      };

      "blog.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.1.3:80";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "downloads.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.2.2:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "media.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.2.2:8081";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "files-webdav.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.5:8090";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "files.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://10.0.3.5:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
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

            # Increase timeouts for large file operations
            proxy_send_timeout 3600s;
            proxy_read_timeout 3600s;
            client_body_timeout 3600s;
            send_timeout 3600s;

            # Set reasonable file size limit
            client_max_body_size 100G;

            # Optimize buffering for large file operations
            client_body_buffer_size 10M;
            proxy_buffering off;
            proxy_request_buffering off;

            # Increase proxy buffer sizes for large responses
            proxy_buffer_size 128k;
            proxy_buffers 4 256k;
            proxy_busy_buffers_size 256k;
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
