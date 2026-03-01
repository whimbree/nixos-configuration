{ config, pkgs, lib, ... }:
let
  restrictiveRobotsTxt = {
    return = ''
      200 "User-agent: *
      Disallow: /"'';
    extraConfig = ''
      default_type text/plain;
    '';
  };
in {
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "whimbree@pm.me";
      dnsProvider = "porkbun";
      credentialsFile = "/services/nginx/porkbun-credentials";
    };

    certs."whimsical.cloud" = {
      domain = "*.whimsical.cloud";
      extraDomainNames = [ "whimsical.cloud" ];
      dnsProvider = "porkbun";
      credentialsFile = "/services/nginx/porkbun-credentials";
      group = "nginx";
    };
  };

  services.nginx = {
    enable = true;
    package = pkgs.nginxMainline;

    user = "nginx";
    group = "nginx";

    sslCiphers =
      "ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384";
    sslProtocols = "TLSv1.2 TLSv1.3";

    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    appendHttpConfig = ''
      # Security headers for all sites
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-Frame-Options "DENY" always;
      add_header X-Robots-Tag "noindex, nofollow" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;

      # Hide backend headers to avoid duplicates
      proxy_hide_header X-Robots-Tag;
      proxy_hide_header X-Powered-By;
      proxy_hide_header Server;

      # Disable server tokens
      server_tokens off;
    '';

    commonHttpConfig = ''
      proxy_connect_timeout 60s;
      proxy_send_timeout 300s;
      proxy_read_timeout 300s;
      client_body_timeout 60s;
      client_header_timeout 60s;
      send_timeout 300s;
      keepalive_timeout 65s;

      client_body_buffer_size 128k;
      proxy_buffering on;
      proxy_request_buffering on;

      proxy_buffer_size 4k;
      proxy_buffers 8 4k;
      proxy_busy_buffers_size 8k;
    '';

    virtualHosts = {
      "_" = {
        default = true;
        useACMEHost = "whimsical.cloud";
        forceSSL = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = { return = "444"; };
      };

      "headscale.whimsical.cloud" = {
        useACMEHost = "whimsical.cloud";
        forceSSL = true;
        http2 = true;
        locations."/robots.txt" = restrictiveRobotsTxt;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8080/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect http:// https://;
            proxy_buffering off;
          '';
        };
        locations."/admin/" = {
          proxyPass = "http://127.0.0.1:3000";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect http:// https://;
            proxy_buffering off;
          '';
        };
      };
    };
  };
}
