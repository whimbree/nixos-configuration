{ lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  # Generate networking from registry data
  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Restrictive robots.txt for all services
  restrictiveRobotsTxt = {
    return = ''
      200 "User-agent: *
      Disallow: /"'';
    extraConfig = ''
      add_header Content-Type text/plain;
    '';
  };

  defaultAnubisBotPolicy = {
    bots = [
      {
        name = "cloudflare-workers";
        headers_regex = { CF-Worker = ".*"; };
        action = "DENY";
      }
      {
        name = "well-known";
        path_regex = "^/.well-known/.*$";
        action = "ALLOW";
      }
      {
        name = "favicon";
        path_regex = "^/favicon.ico$";
        action = "ALLOW";
      }
      {
        name = "robots-txt";
        path_regex = "^/robots.txt$";
        action = "ALLOW";
      }
      {
        name = "generic-browser";
        user_agent_regex = "Mozilla";
        action = "CHALLENGE";
      }
      {
        name = "generic-bot-catchall";
        user_agent_regex = "(?i:bot|crawler)";
        action = "CHALLENGE";
        challenge = {
          difficulty = 15;
          report_as = 5;
          algorithm = "slow";
        };
      }
    ];
  };

  defaultAnubisSettings = {
    BIND_NETWORK = "tcp";
    DIFFICULTY = 5;
    COOKIE_EXPIRATION_TIME = "24h";
  };

  mkAnubisInstance = settings: {
    settings = defaultAnubisSettings // settings;
    botPolicy = defaultAnubisBotPolicy;
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

    certs."bspwr.com" = {
      domain = "*.bspwr.com";
      extraDomainNames = [ "bspwr.com" ]; # Include bare domain too
      dnsProvider = "porkbun";
      credentialsFile = "/var/lib/acme/porkbun-credentials";
      group = "nginx";
    };

    certs."bree.zip" = {
      domain = "*.bree.zip";
      extraDomainNames = [ "bree.zip" ]; # Include bare domain too
      dnsProvider = "porkbun";
      credentialsFile = "/var/lib/acme/porkbun-credentials";
      group = "nginx";
    };

    certs."gaybottoms.org" = {
      domain = "*.gaybottoms.org";
      extraDomainNames = [ "gaybottoms.org" ]; # Include bare domain too
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
      # Default catch-all server
      "_" = {
        default = true;
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = { return = "404"; };
      };

      # All subdomains use the same wildcard cert
      "deluge.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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

      "lidarr.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://10.0.1.1:8686"; # Lidarr web UI port
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      # "jellyseerr.bspwr.com" = {
      #   useACMEHost = "bspwr.com";
      #   forceSSL = true;
      #   locations."/robots.txt" = restrictiveRobotsTxt;
      #   locations."/" = {
      #     proxyPass = "http://10.0.1.1:5055"; # Jellyseerr web UI port
      #     proxyWebsockets = true;
      #     extraConfig = ''
      #       proxy_set_header Host $host;
      #       proxy_set_header X-Real-IP $remote_addr;
      #       proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      #       proxy_set_header X-Forwarded-Proto $scheme;
      #     '';
      #   };
      # };

      "jellyfin.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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

      "bree.zip" = {
        useACMEHost = "bree.zip";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
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
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://10.0.3.5:8080";
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

      "alex-duplicati.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
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

      "metube.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://10.0.1.4:8081";
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

      "redlib.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://localhost:7676";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "invidious.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://localhost:3000"; # through anubis
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "slskd.bspwr.com" = {
        useACMEHost = "bspwr.com";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://10.0.1.4:5030";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };

      "chat.gaybottoms.org" = {
        useACMEHost = "gaybottoms.org";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://10.0.3.7:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Increase timeouts for large file operations
            proxy_send_timeout 360s;
            proxy_read_timeout 360s;
            client_body_timeout 360s;
            send_timeout 360s;

            # Set reasonable file size limit
            # Allow large Fluxer attachments
            client_max_body_size 10G;

            # Disable buffering for WebSocket/real-time traffic
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };

      "gaybottoms.org" = {
        useACMEHost = "gaybottoms.org";
        forceSSL = true;
        locations."/" = {
          return = "301 https://chat.gaybottoms.org$request_uri";
        };
      };

      "lk.gaybottoms.org" = {
        useACMEHost = "gaybottoms.org";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://10.0.1.5:7880";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # Disable buffering for WebSocket/real-time traffic
            proxy_buffering off;
            proxy_request_buffering off;
          '';
        };
      };

      # Add more services here - all using the same wildcard cert
    };
  };

  services.anubis.instances = {
    redlib = mkAnubisInstance {
      TARGET = "http://10.0.1.4:7676";
      BIND = ":7676";
      REDIRECT_DOMAINS = "redlib.bspwr.com";
    };
    invidious = mkAnubisInstance {
      TARGET = "http://10.0.1.4:3000";
      BIND = ":3000";
      REDIRECT_DOMAINS = "invidious.bspwr.com";
    };
  };

  # Dynamic DNS updater service
  systemd.services.porkbun-ddns = {
    description = "Update Porkbun DNS records with current public IP";
    after = [ "network-online.target" "create-porkbun-credentials.service" ];
    wants = [ "network-online.target" "create-porkbun-credentials.service" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/var/lib/acme/porkbun-credentials";
    };
    script = ''
      set -euo pipefail

      DOMAINS=("bspwr.com" "bree.zip" "gaybottoms.org")
      RECORDS=("" "*")

      get_public_ip() {
        ${pkgs.dnsutils}/bin/dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]' || \
        ${pkgs.curl}/bin/curl -sf --max-time 5 https://icanhazip.com | ${pkgs.coreutils}/bin/tr -d '[:space:]' || \
        ${pkgs.curl}/bin/curl -sf --max-time 5 https://ifconfig.me | ${pkgs.coreutils}/bin/tr -d '[:space:]' || \
        { echo "Failed to fetch public IP" >&2; return 1; }
      }

      CURRENT_IP=$(get_public_ip)

      if [[ ! "$CURRENT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid IP address: $CURRENT_IP" >&2
        exit 1
      fi

      echo "Current IP: $CURRENT_IP"

      failed=0
      updated=0

      for domain in "''${DOMAINS[@]}"; do
        for record in "''${RECORDS[@]}"; do
          if [[ -z "$record" ]]; then
            label="$domain"
            fqdn="$domain"
          else
            label="$record.$domain"
            fqdn="$record.$domain"
          fi

          dns_ip=$(${pkgs.dnsutils}/bin/dig +short "$fqdn" A @1.1.1.1 2>/dev/null | ${pkgs.coreutils}/bin/tail -n1)
          if [[ "$dns_ip" == "$CURRENT_IP" ]]; then
            echo "$label already correct"
            continue
          fi

          echo "Updating $label ($dns_ip -> $CURRENT_IP)"

          response=$(${pkgs.curl}/bin/curl -s --max-time 10 \
            -X POST "https://api.porkbun.com/api/json/v3/dns/editByNameType/$domain/A/$record" \
            -H "Content-Type: application/json" \
            -d "{
              \"apikey\": \"$PORKBUN_API_KEY\",
              \"secretapikey\": \"$PORKBUN_SECRET_API_KEY\",
              \"content\": \"$CURRENT_IP\",
              \"ttl\": \"60\"
            }")

          if [[ -z "$response" ]]; then
            echo "No response from Porkbun API for $label" >&2
            failed=1
            continue
          fi

          status=$(echo "$response" | ${pkgs.jq}/bin/jq -r '.status // "error"' 2>/dev/null) || status="error"

          if [[ "$status" != "SUCCESS" ]]; then
            echo "Failed to update $label: $response" >&2
            failed=1
            continue
          fi

          echo "Successfully updated $label"
          updated=$((updated + 1))
        done
      done

      if [[ $failed -eq 1 ]]; then
        echo "Some DNS updates failed (updated $updated records)" >&2
        exit 1
      fi

      if [[ $updated -gt 0 ]]; then
        echo "Updated $updated records to $CURRENT_IP"
      else
        echo "All records already correct ($CURRENT_IP)"
      fi
    '';
  };

  systemd.timers.porkbun-ddns = {
    description = "Run DDNS updater every 30 seconds";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1s";
      OnUnitInactiveSec = "30s";
      AccuracySec = "5s";
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
    before = [ "acme-bspwr.com.service" "acme-bree.zip.service" "acme-gaybottoms.org.service" "nginx.service" ];
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

  # SSH, HTTP, HTTPS
  networking.firewall = {
    allowedTCPPorts = [ 22 80 443 ];
  };
}
