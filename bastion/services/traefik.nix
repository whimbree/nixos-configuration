{ config, pkgs, lib, ... }:
let
  prometheusYml = pkgs.writeTextDir "prometheus.yml" ''
    global:
    scrape_interval:     15s 
    evaluation_interval: 15s 
    external_labels:
        monitor: 'codelab-monitor'

    rule_files:
    - 'prometheus.rules'

    scrape_configs:
    - job_name: 'prometheus'
        scrape_interval: 5s
        static_configs:
        - targets: ['localhost:9090']
    - job_name: 'traefik'
        scrape_interval: 5s
        metrics_path: '/metrics'
        static_configs:
        - targets: ['traefik:8082']
  '';

  prometheusRules = pkgs.writeTextDir "prometheus.rules" ''
    ###########################
    # Alert - Monitoring Host #
    ###########################
    ALERT host_down
     IF up{} == 0
     FOR 30s
     LABELS { severity = "critical" }
     ANNOTATIONS {
          summary = "Monitoring host production",
          description = "{{ $labels.job }} is down.",
          runbook = "https://prometheus.io/docs/alerting/configuration/",
      }

    ######################
    # Alert - Disk Usage #
    #################### #
    ALERT disk_usage_warning
     IF ((node_filesystem_size{fstype="ext4",mountpoint="/"} - node_filesystem_avail{fstype="ext4",mountpoint="/"} ) / (node_filesystem_size{fstype="ext4",mountpoint="/"})) * 100 >= 65
     FOR 1m
     LABELS { severity = "critical" }
     ANNOTATIONS {
          summary = "Server storage is almost full",
          description = "Disk usage on {{ $labels.job }} is {{ humanize $value }}%. Reported by instance {{ $labels.instance }}.",
          runbook = "https://prometheus.io/docs/alerting/configuration/",
      }


    ####################
    # Alert - CPU Load #
    ####################
    ALERT high_cpu_load
     IF 100 * (1 - avg by(instance)(irate(node_cpu{mode='idle'}[1m]))) >= 65
     FOR 1m
     LABELS { severity = "critical" }
     ANNOTATIONS {
          summary = "Server under high load",
          description = "High CPU Load on {{ $labels.job }} is {{ humanize $value }}. Reported by instance {{ $labels.instance }}.",
          runbook = "https://prometheus.io/docs/alerting/configuration/",
      }


    #######################
    # Alert - Memory Load #
    #######################
    ALERT high_memory_load
     IF (((node_memory_MemTotal{} - node_memory_MemFree{} ) / (node_memory_MemTotal{}) )* 100) >= 90
     FOR 1m
     LABELS { severity = "critical" }
     ANNOTATIONS {
          summary = "Server under high memory load",
          description = "High Memory Load on {{ $labels.job }} is {{ humanize $value}}%. Reported by instance {{ $labels.instance }}",
          runbook = "https://prometheus.io/docs/alerting/configuration/",
      }
  '';

in {
  systemd.services.docker-create-network-traefik = {
    enable = true;
    description = "Create traefik docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-traefik" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create traefik || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."traefik" = {
    autoStart = true;
    image = "docker.io/traefik:v2.9.9";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "/services/traefik/letsencrypt:/etc/traefik/letsencrypt"
      "/services/traefik/logs:/etc/traefik/logs"
      "/services/traefik/traefik.yml:/etc/traefik/traefik.yml"
      "/services/traefik/config.yml:/etc/traefik/config.yml"
    ];
    ports = [
      "80:80" # HTTP
      "443:443" # HTTPS
    ];
    dependsOn = [ "create-network-traefik" ];
    extraOptions = [
      # networks
      "--network=traefik"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=traefik"
      "--label"
      "traefik.http.routers.traefik.rule=Host(`traefik.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.traefik.entrypoints=websecure"
      "--label"
      "traefik.http.routers.traefik.tls=true"
      "--label"
      "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.traefik.service=api@internal"
      "--label"
      "traefik.http.routers.traefik.middlewares=local-allowlist@file, default@file"
      ## dependheal
      "--label"
      "dependheal.enable=true"
      ### additional networks
      "--label"
      "dependheal.networks=arr, blog, filebrowser, gitea, headscale, heimdall, immich, incognito, jellyfin, jenkins, lxdware, matrix, meet.jitsi, minecraft-aof6, minecraft-atm7, minecraft-atm8, minecraft-enigmatica2, minecraft-vanilla, mullvad-sweden, mullvad-usa, nextcloud, photoprism, piped, portainer, poste, projectsend, revolt, traefik, virt-manager, webdav"
    ];
  };

  virtualisation.oci-containers.containers."grafana" = {
    autoStart = true;
    image = "docker.io/grafana/grafana:8.5.22";
    volumes = [ "/services/traefik/grafana:/var/lib/grafana" ];
    environment = {
      GF_INSTALL_PLUGINS = "grafana-piechart-panel,jdbranham-diagram-panel";
    };
    dependsOn = [ "create-network-traefik" ];
    extraOptions = [
      # user
      "--user=0"
      # networks
      "--network=traefik"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=traefik"
      "--label"
      "traefik.http.routers.grafana.rule=Host(`grafana.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.grafana.entrypoints=websecure"
      "--label"
      "traefik.http.routers.grafana.tls=true"
      "--label"
      "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.grafana.service=grafana"
      "--label"
      "traefik.http.routers.grafana.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.grafana.loadbalancer.server.port=3000"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."prometheus" = {
    autoStart = true;
    image = "docker.io/prom/prometheus:v1.7.1";
    volumes = [
      "${prometheusYml}/prometheus.yml:/etc/prometheus/prometheus.yml:ro"
      "${prometheusRules}/prometheus.rules:/etc/prometheus/prometheus.rules:ro"
      "/services/traefik/prometheusdb:/prometheus/data:rw"
    ];
    cmd = [
      "-config.file=/etc/prometheus/prometheus.yml"
      "-web.external-url=http://prometheus:9090/"
      "-web.route-prefix=/"
    ];
    dependsOn = [ "create-network-traefik" ];
    extraOptions = [
      # networks
      "--network=traefik"
      # labels
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."goaccess" = {
    autoStart = true;
    image = "docker.io/xavierh/goaccess-for-nginxproxymanager:latest";
    volumes = [
      "/services/traefik/logs:/opt/log"
      "/services/traefik/goaccess:/opt/custom"
    ];
    environment = {
      PUID = "0";
      PGID = "0";
      TZ = "America/New_York";
      DEBUG = "False";
      EXCLUDE_IPS = "127.0.0.1";
      LOG_TYPE = "TRAEFIK";
    };
    dependsOn = [ "create-network-traefik" ];
    extraOptions = [
      # networks
      "--network=traefik"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:7880 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "6"
      "--health-timeout"
      "2s"
      "--health-start-period"
      "10s"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=traefik"
      "--label"
      "traefik.http.routers.goaccess.rule=Host(`goaccess.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.goaccess.entrypoints=websecure"
      "--label"
      "traefik.http.routers.goaccess.tls=true"
      "--label"
      "traefik.http.routers.goaccess.tls.certresolver=letsencrypt"
      "--label"
      "traefik.http.routers.goaccess.service=goaccess"
      "--label"
      "traefik.http.routers.goaccess.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.goaccess.loadbalancer.server.port=7880"
      ## dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."crowdsec" = {
    autoStart = true;
    image = "docker.io/crowdsecurity/crowdsec:latest";
    volumes = [
      "/services/traefik/crowdsec/data:/var/lib/crowdsec/data"
      "/services/traefik/crowdsec:/etc/crowdsec"
      "/services/traefik/logs:/var/log/traefik:ro"
      "/var/log/auth.log:/var/log/auth.log:ro"
      "/services/traefik/endlessh/config/logs/endlessh:/var/log/endlessh:ro"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
    };
    dependsOn = [ "create-network-traefik" ];
    extraOptions = [
      # networks
      "--network=traefik"
    ];
  };

  virtualisation.oci-containers.containers."crowdsec-traefik-bouncer" = {
    autoStart = true;
    image = "docker.io/fbonalair/traefik-crowdsec-bouncer:latest";
    environment = {
      CROWDSEC_AGENT_HOST = "crowdsec:8080";
      GIN_MODE = "release";
    };
    environmentFiles = [ "/services/traefik/crowdsec/.env" ];
    dependsOn = [ "create-network-traefik" "crowdsec" ];
    extraOptions = [
      # networks
      "--network=traefik"
    ];
  };

  virtualisation.oci-containers.containers."endlessh" = {
    autoStart = true;
    image = "docker.io/linuxserver/endlessh:latest";
    volumes = [ "/services/traefik/endlessh/config:/config" ];
    environment = { LOGFILE = "true"; };
    ports = [ "2200:2222" ];
  };
}
