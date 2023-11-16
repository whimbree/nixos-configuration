{ config, pkgs, lib, ... }:
let
  pipedConfig = pkgs.writeTextDir "config.properties" ''
    # The port to Listen on.
    PORT: 8080

    # The number of workers to use for the server
    HTTP_WORKERS: 4

    # Proxy
    PROXY_PART: https://pipedproxy.bspwr.com

    # Outgoing HTTP Proxy - eg: 127.0.0.1:8118
    # HTTP_PROXY: 127.0.0.1:8118

    # Captcha Parameters
    # CAPTCHA_BASE_URL: https://api.capmonster.cloud/
    # CAPTCHA_API_KEY: INSERT_HERE

    # Public API URL
    API_URL: https://pipedapi.bspwr.com

    # Public Frontend URL
    FRONTEND_URL: https://piped.bspwr.com

    # Enable haveibeenpwned compromised password API
    COMPROMISED_PASSWORD_CHECK: true

    # Disable Registration
    DISABLE_REGISTRATION: false

    # Feed Retention Time in Days
    FEED_RETENTION: 30

    # Hibernate properties
    hibernate.connection.url: jdbc:postgresql://piped-postgres:5432/piped
    hibernate.connection.driver_class: org.postgresql.Driver
    hibernate.dialect: org.hibernate.dialect.PostgreSQLDialect
    hibernate.connection.username: piped
    hibernate.connection.password: piped
  '';

  pipedNginxConfig = pkgs.writeTextDir "nginx.conf" ''
    user root;
    worker_processes auto;

    error_log /var/log/nginx/error.log notice;
    pid /var/run/nginx.pid;


    events {
        worker_connections 1024;
    }

    http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;

        server_names_hash_bucket_size 128;

        access_log off;

        sendfile on;
        tcp_nodelay on;

        keepalive_timeout 65;

        resolver 127.0.0.11 ipv6=off valid=10s;

        include /etc/nginx/conf.d/*.conf;
    }
  '';

  pipedApiConfig = pkgs.writeTextDir "pipedapi.conf" ''
    proxy_cache_path /tmp/pipedapi_cache levels=1:2 keys_zone=pipedapi:4m max_size=2g inactive=60m use_temp_path=off;

    server {
        listen 80;
        server_name pipedapi.bspwr.com;

        set $backend "http://piped-backend:8080";

        location / {
            proxy_cache pipedapi;
            proxy_pass $backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "keep-alive";
        }
    }
  '';

  pipedProxyConfig = pkgs.writeTextDir "pipedproxy.conf" ''
    server {
        listen 80;
        server_name pipedproxy.bspwr.com;

        location ~ (/videoplayback|/api/v4/|/api/manifest/) {
            include snippets/ytproxy.conf;
            add_header Cache-Control private always;
        }

        location / {
            include snippets/ytproxy.conf;
            add_header Cache-Control "public, max-age=604800";
        }
    }
  '';

  pipedFrontendConfig = pkgs.writeTextDir "pipedfrontend.conf" ''
    server {
        listen 80;
        server_name piped.bspwr.com;

        set $backend "http://piped-frontend:80";

        location / {
            proxy_pass $backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "keep-alive";
        }
    }
  '';

  pipedYtproxyConfig = pkgs.writeTextDir "ytproxy.conf" ''
    proxy_buffering on;
    proxy_buffers 1024 16k;
    proxy_set_header X-Forwarded-For "";
    proxy_set_header CF-Connecting-IP "";
    proxy_hide_header "alt-svc";
    sendfile on;
    sendfile_max_chunk 512k;
    tcp_nopush on;
    aio threads=default;
    aio_write on;
    directio 16m;
    proxy_hide_header Cache-Control;
    proxy_hide_header etag;
    proxy_http_version 1.1;
    proxy_set_header Connection keep-alive;
    proxy_max_temp_file_size 32m;
    access_log off;
    proxy_pass http://unix:/var/run/ytproxy/actix.sock;
  '';

in {
  systemd.services.docker-create-network-piped = {
    enable = true;
    description = "Create piped docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-piped" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create piped || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."piped-frontend" = {
    autoStart = true;
    image = "ghcr.io/whimbree/piped-frontend:latest";
    environment = { PIPED_API_URL = "pipedapi.bspwr.com"; };
    dependsOn = [ "create-network-piped" ];
    extraOptions = [
      # networks
      "--network=piped"
    ];
  };

  virtualisation.oci-containers.containers."piped-proxy" = {
    autoStart = true;
    image = "docker.io/1337kavin/piped-proxy:latest";
    volumes = [ "/services/incognito/piped-proxy:/app/socket" ];
    environment = { UDS = "1"; };
    dependsOn = [ "create-network-piped" ];
    extraOptions = [
      # networks
      "--network=piped"
    ];
  };

  virtualisation.oci-containers.containers."piped-backend" = {
    autoStart = true;
    image = "docker.io/1337kavin/piped:latest";
    volumes = [ "${pipedConfig}/config.properties:/app/config.properties:ro" ];
    environment = { TZ = "America/New_York"; };
    dependsOn = [ "create-network-piped" "piped-postgres" ];
    extraOptions = [
      # networks
      "--network=piped"
    ];
  };

  virtualisation.oci-containers.containers."piped-postgres" = {
    autoStart = true;
    image = "docker.io/postgres:13-alpine";
    volumes =
      [ "/services/incognito/piped-postgres/data:/var/lib/postgresql/data" ];
    environment = {
      POSTGRES_DB = "piped";
      POSTGRES_USER = "piped";
      POSTGRES_PASSWORD = "piped";
    };
    dependsOn = [ "create-network-piped" ];
    extraOptions = [
      # networks
      "--network=piped"
    ];
  };

  virtualisation.oci-containers.containers."piped-nginx" = {
    autoStart = true;
    image = "docker.io/nginx:mainline-alpine";
    volumes = [
      "${pipedNginxConfig}/nginx.conf:/etc/nginx/nginx.conf:ro"
      "${pipedApiConfig}/pipedapi.conf:/etc/nginx/conf.d/pipedapi.conf:ro"
      "${pipedProxyConfig}/pipedproxy.conf:/etc/nginx/conf.d/pipedproxy.conf:ro"
      "${pipedFrontendConfig}/pipedfrontend.conf:/etc/nginx/conf.d/pipedfrontend.conf:ro"
      "${pipedYtproxyConfig}/ytproxy.conf:/etc/nginx/snippets/ytproxy.conf:ro"
      "/services/incognito/piped-proxy:/var/run/ytproxy"
    ];
    environment = {
      POSTGRES_DB = "piped";
      POSTGRES_USER = "piped";
      POSTGRES_PASSWORD = "piped";
    };
    dependsOn = [ "create-network-piped" ];
    extraOptions = [
      # networks
      "--network=piped"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=piped"
      "--label"
      "traefik.http.routers.piped.rule=Host(`piped.bspwr.com`) || Host(`pipedapi.bspwr.com`) || Host(`pipedproxy.bspwr.com`)"
      "--label"
      "traefik.http.routers.piped.entrypoints=websecure"
      "--label"
      "traefik.http.routers.piped.tls=true"
      "--label"
      "traefik.http.routers.piped.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.piped.service=piped"
      "--label"
      "traefik.http.routers.piped.middlewares=default@file"
      "--label"
      "traefik.http.services.piped.loadbalancer.server.port=80"
    ];
  };
}
