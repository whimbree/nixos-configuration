{ config, pkgs, lib, ... }:
let
  elementConfig = pkgs.writeTextDir "element-config.json" ''
    {
        "default_server_config": {
            "m.homeserver": {
                "base_url": "https://matrix.bspwr.com",
                "server_name": "matrix.bspwr.com"
            },
            "m.identity_server": {
                "base_url": "https://vector.im"
            }
        },
        "brand": "Element",
        "integrations_ui_url": "https://scalar.vector.im/",
        "integrations_rest_url": "https://scalar.vector.im/api",
        "integrations_widgets_urls": [
            "https://scalar.vector.im/_matrix/integrations/v1",
            "https://scalar.vector.im/api",
            "https://scalar-staging.vector.im/_matrix/integrations/v1",
            "https://scalar-staging.vector.im/api",
            "https://scalar-staging.riot.im/scalar/api"
        ],
        "bug_report_endpoint_url": "https://element.io/bugreports/submit",
        "uisi_autorageshake_app": "element-auto-uisi",
        "showLabsSettings": true,
        "roomDirectory": {
            "servers": ["matrix.bspwr.com", "matrix.org", "gitter.im", "libera.chat"]
        },
        "enable_presence_by_hs_url": {
            "https://matrix.org": false,
            "https://matrix-client.matrix.org": false
        },
        "terms_and_conditions_links": [
            {
                "url": "https://element.io/privacy",
                "text": "Privacy Policy"
            },
            {
                "url": "https://element.io/cookie-policy",
                "text": "Cookie Policy"
            }
        ],
        "posthog": {
            "projectApiKey": "phc_Jzsm6DTm6V2705zeU5dcNvQDlonOR68XvX2sh1sEOHO",
            "apiHost": "https://posthog.element.io"
        },
        "privacy_policy_url": "https://element.io/cookie-policy",
        "features": {
            "feature_spotlight": true,
            "feature_video_rooms": true
        },
        "element_call": {
            "url": "https://element-call.bspwr.com"
        },
        "jitsi": {
            "preferredDomain": "jitsi.bspwr.com"
        },
        "map_style_url": "https://api.maptiler.com/maps/streets/style.json?key=fU3vlMsMn4Jb6dnEIFsx"
    }
  '';

  elementCallConfig = pkgs.writeTextDir "element-call-config.json" ''
    {
        "default_server_config": {
          "m.homeserver": {
            "base_url": "https://matrix.bspwr.com",
            "server_name": "matrix.bspwr.com"
          }
        }
      }
  '';

in {
  systemd.services.docker-create-network-matrix = {
    enable = true;
    description = "Create matrix docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-matrix" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create matrix || true
      '';
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."matrix-element" = {
    autoStart = true;
    image = "docker.io/vectorim/element-web:latest";
    volumes = [ "${elementConfig}/element-config.json:/app/config.json:ro" ];
    dependsOn = [ "create-network-matrix" ];
    extraOptions = [
      # networks
      "--network=matrix"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=matrix"
      "--label"
      "traefik.http.routers.element.rule=Host(`element.bspwr.com`)"
      "--label"
      "traefik.http.routers.element.entrypoints=websecure"
      "--label"
      "traefik.http.routers.element.tls=true"
      "--label"
      "traefik.http.routers.element.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.element.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.element.service=element"
      "--label"
      "traefik.http.routers.element.middlewares=default@file"
      "--label"
      "traefik.http.services.element.loadbalancer.server.port=80"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."matrix-element-call" = {
    autoStart = true;
    image = "ghcr.io/vector-im/element-call:latest";
    volumes =
      [ "${elementCallConfig}/element-call-config.json:/app/config.json:ro" ];
    dependsOn = [ "create-network-matrix" ];
    extraOptions = [
      # networks
      "--network=matrix"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=matrix"
      "--label"
      "traefik.http.routers.element-call.rule=Host(`element-call.bspwr.com`)"
      "--label"
      "traefik.http.routers.element-call.entrypoints=websecure"
      "--label"
      "traefik.http.routers.element-call.tls=true"
      "--label"
      "traefik.http.routers.element-call.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.element-call.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.element-call.service=element-call"
      "--label"
      "traefik.http.routers.element-call.middlewares=default@file"
      "--label"
      "traefik.http.services.element-call.loadbalancer.server.port=8080"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."matrix-synapse" = {
    autoStart = true;
    image = "docker.io/matrixdotorg/synapse:latest";
    volumes = [ "/services/matrix/synapse:/data" ];
    dependsOn = [ "create-network-matrix" ];
    extraOptions = [
      # networks
      "--network=matrix"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=matrix"
      "--label"
      "traefik.http.routers.matrix.rule=Host(`matrix.bspwr.com`)"
      "--label"
      "traefik.http.routers.matrix.entrypoints=websecure"
      "--label"
      "traefik.http.routers.matrix.tls=true"
      "--label"
      "traefik.http.routers.matrix.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.matrix.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.matrix.service=matrix"
      "--label"
      "traefik.http.routers.matrix.middlewares=default@file"
      "--label"
      "traefik.http.services.matrix.loadbalancer.server.port=8008"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."matrix-postgres" = {
    autoStart = true;
    image = "docker.io/postgres:11";
    volumes = [ "/services/matrix/postgresdata:/var/lib/postgresql/data" ];
    environment = {
      POSTGRES_DB = "synapse";
      POSTGRES_USER = "synapse";
      POSTGRES_PASSWORD = "synapse";
      POSTGRES_INITDB_ARGS = "--lc-collate C --lc-ctype C --encoding UTF8";
    };
    dependsOn = [ "create-network-matrix" ];
    extraOptions = [
      # networks
      "--network=matrix"
      # labels
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };
}
