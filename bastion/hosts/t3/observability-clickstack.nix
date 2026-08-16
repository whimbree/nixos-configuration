{
  config,
  lib,
  pkgs,
  observability,
  ...
}:
let
  otlpGrpcPort = toString observability.ports.otlpGrpc;
  hyperdxPort = toString observability.ports.hyperdx;
  hyperdxFrontendUrl =
    if observability.public.enabled then
      observability.public.hyperdxUrl
    else
      observability.tailnet.hyperdxUrl;

  # Compatible tuple from ClickStack release @hyperdx/otel-collector@2.35.0,
  # commit fb1a2ff6002cbc814e87e3ecf59e016b979517fd. Tags make the
  # reviewed versions visible; linux/amd64 manifest digests make references
  # immutable.
  images = {
    clickhouse = "docker.io/clickhouse/clickhouse-server:26.5-alpine@sha256:d835fa2d1a93cc25ace63ca7167cc40944d111d351cc56c466fb6851ffe4fe84";
    collector = "docker.clickhouse.com/clickhouse/clickstack-otel-collector:2.35.0@sha256:1b6b2c9de2182256311ea928215d23faf7f6609c77a1c397a9a576970df4b89f";
    hyperdx = "docker.hyperdx.io/hyperdx/hyperdx:2.35.0@sha256:8393af3d166b59778171e8bd78f0e0175c2053e5a39c85c8452520ede0d08ea5";
    mongo = "docker.io/library/mongo:5.0.32-focal@sha256:b2ace5ddbeb6d2e035aab54c486b8145bef83cff7bc3d518598b8449db74f3aa";
  };

  stackSecretNames = [
    "clickhouse-admin-password"
    "clickhouse-ingest-password"
    "clickhouse-query-password"
    "mongo-root-password"
    "hyperdx-session-secret"
    "hyperdx-api-key"
  ];

  defaultSources = [
    {
      from = {
        databaseName = "otel";
        tableName = "otel_logs";
      };
      kind = "log";
      timestampValueExpression = "Timestamp";
      displayedTimestampValueExpression = "Timestamp";
      name = "Logs";
      implicitColumnExpression = "Body";
      serviceNameExpression = "ServiceName";
      bodyExpression = "Body";
      eventAttributesExpression = "LogAttributes";
      resourceAttributesExpression = "ResourceAttributes";
      defaultTableSelectExpression = "Timestamp,ServiceName,SeverityText,Body";
      severityTextExpression = "SeverityText";
      traceIdExpression = "TraceId";
      spanIdExpression = "SpanId";
      # No metadataMaterializedViews: the rollup tables only exist under the
      # goose-migration schema, which CREATE_LEGACY_SCHEMA=true skips. HyperDX
      # detects their absence and falls back to raw scans.
      connection = "Homelab ClickHouse";
      metricSourceId = "Metrics";
    }
    {
      from = {
        databaseName = "otel";
        tableName = "";
      };
      kind = "metric";
      timestampValueExpression = "TimeUnix";
      name = "Metrics";
      resourceAttributesExpression = "ResourceAttributes";
      metricTables = {
        gauge = "otel_metrics_gauge";
        histogram = "otel_metrics_histogram";
        sum = "otel_metrics_sum";
      };
      connection = "Homelab ClickHouse";
      logSourceId = "Logs";
    }
  ];

  # Server-level settings merge from config.d; per-user profile settings are
  # only honored from the users-config chain (users.d), so they must be two
  # separate fragments — a profiles block under config.d is silently ignored.
  clickhouseServerConfig = pkgs.writeText "clickstack-homelab-server.xml" ''
    <clickhouse>
      <logger>
        <!-- Avoid a query-log feedback loop when container output is itself
             collected. Preserve warnings/errors in the persistent journal. -->
        <level>warning</level>
        <console>true</console>
        <log remove="remove"/>
        <errorlog remove="remove"/>
      </logger>
      <max_server_memory_usage>3758096384</max_server_memory_usage>
      <max_concurrent_queries>20</max_concurrent_queries>
      <storage_configuration>
        <disks>
          <!-- Staging area on the zvol the server already owns; the backup
               unit (guest root) moves finished backups to the ocean share,
               so the server never needs write access through virtiofs. -->
          <backups>
            <type>local</type>
            <path>/var/lib/clickhouse/backups/</path>
          </backups>
        </disks>
      </storage_configuration>
      <backups>
        <allowed_disk>backups</allowed_disk>
      </backups>
    </clickhouse>
  '';

  clickhouseUsersConfig = pkgs.writeText "clickstack-homelab-users.xml" ''
    <clickhouse>
      <profiles>
        <default>
          <max_memory_usage>2147483648</max_memory_usage>
          <max_threads>4</max_threads>
          <log_queries>0</log_queries>
        </default>
      </profiles>
    </clickhouse>
  '';

  # Runs INSIDE the clickhouse container (fed to its shell over stdin by the
  # clickstack-users-ready unit), so $CLICKHOUSE_* expand from the container
  # env and clickhouse-client authenticates as admin from the same env — no
  # secret ever reaches a host process argument or the Nix store. Deliberately
  # NOT a /docker-entrypoint-initdb.d script: that mechanism only runs on an
  # empty data dir and honours the script's shebang, which for a Nix store
  # path points at a /nix/store bash absent from the Alpine image. CREATE OR
  # REPLACE makes this safe to re-run on every start and self-healing.
  clickhouseUsersScript = pkgs.writeText "clickstack-create-users.sh" ''
    set -eu
    clickhouse-client --log_queries=0 --multiquery <<SQL
    CREATE DATABASE IF NOT EXISTS otel;
    CREATE OR REPLACE USER otel_ingest IDENTIFIED WITH sha256_password BY '$CLICKHOUSE_INGEST_PASSWORD';
    GRANT ALL ON otel.* TO otel_ingest;
    CREATE OR REPLACE USER hyperdx IDENTIFIED WITH sha256_password BY '$CLICKHOUSE_QUERY_PASSWORD';
    GRANT SELECT ON otel.* TO hyperdx;
    GRANT SELECT ON system.* TO hyperdx;
    SQL
  '';

  # The release's standalone config supplies its ClickStack routing connector
  # and canonical map schema. This overlay gives each signal an independent
  # TTL and a persistent, bounded sending queue.
  collectorConfig = pkgs.writeText "clickstack-collector-homelab.yaml" ''
    extensions:
      file_storage:
        directory: /var/lib/clickstack-collector/queue
        create_directory: true
        fsync: true
        recreate: false
        compaction:
          on_start: true
          on_rebound: true
          directory: /var/lib/clickstack-collector/compaction
          cleanup_on_start: true

    processors:
      # The release default is 1500 MiB, which exceeds this container's
      # 1280 MiB cgroup limit. A distinct processor name is required because
      # collector config files merge leaf-by-leaf.
      memory_limiter/homelab:
        check_interval: 5s
        limit_mib: 1024
        spike_limit_mib: 256

    exporters:
      clickhouse/logs:
        database: ''${env:HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE}
        endpoint: ''${env:CLICKHOUSE_ENDPOINT}
        username: ''${env:CLICKHOUSE_USER}
        password: ''${env:CLICKHOUSE_PASSWORD}
        ttl: 2880h
        timeout: 10s
        create_schema: true
        retry_on_failure:
          enabled: true
          initial_interval: 5s
          max_interval: 30s
          max_elapsed_time: 0s
        sending_queue:
          enabled: true
          storage: file_storage
          num_consumers: 4
          # Byte-bounded queues: the four ceilings below total 18 GiB on the
          # 32 GiB collector volume, leaving slack for bbolt compaction copies.
          sizer: bytes
          queue_size: 10737418240 # 10 GiB
      clickhouse/metrics:
        database: ''${env:HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE}
        endpoint: ''${env:CLICKHOUSE_ENDPOINT}
        username: ''${env:CLICKHOUSE_USER}
        password: ''${env:CLICKHOUSE_PASSWORD}
        ttl: 720h
        timeout: 10s
        create_schema: true
        retry_on_failure:
          enabled: true
          initial_interval: 5s
          max_interval: 30s
          max_elapsed_time: 0s
        sending_queue:
          enabled: true
          storage: file_storage
          num_consumers: 4
          sizer: bytes
          queue_size: 6442450944 # 6 GiB
      clickhouse/traces:
        database: ''${env:HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE}
        endpoint: ''${env:CLICKHOUSE_ENDPOINT}
        username: ''${env:CLICKHOUSE_USER}
        password: ''${env:CLICKHOUSE_PASSWORD}
        ttl: 720h
        timeout: 10s
        create_schema: true
        retry_on_failure:
          enabled: true
          max_elapsed_time: 0s
        sending_queue:
          enabled: true
          storage: file_storage
          sizer: bytes
          queue_size: 1073741824 # 1 GiB
      clickhouse/sessions:
        database: ''${env:HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE}
        endpoint: ''${env:CLICKHOUSE_ENDPOINT}
        username: ''${env:CLICKHOUSE_USER}
        password: ''${env:CLICKHOUSE_PASSWORD}
        ttl: 720h
        logs_table_name: hyperdx_sessions
        timeout: 10s
        create_schema: true
        retry_on_failure:
          enabled: true
          max_elapsed_time: 0s
        sending_queue:
          enabled: true
          storage: file_storage
          sizer: bytes
          queue_size: 1073741824 # 1 GiB

    service:
      extensions: [health_check, file_storage]
      pipelines:
        traces:
          processors: [memory_limiter/homelab, batch]
          exporters: [clickhouse/traces]
        metrics:
          processors: [memory_limiter/homelab, batch]
          exporters: [clickhouse/metrics]
        logs/out-default:
          processors: [memory_limiter/homelab, transform, batch]
          exporters: [clickhouse/logs]
        logs/out-rrweb:
          processors: [memory_limiter/homelab, batch]
          exporters: [clickhouse/sessions]
  '';

  containerUnit = name: "podman-clickstack-${name}.service";
  stackContainerUnits = map containerUnit [
    "clickhouse"
    "mongo"
    "collector"
    "hyperdx"
  ];

  mkContainerService =
    {
      after,
      requires,
      mounts,
    }:
    {
      inherit after requires;
      unitConfig.RequiresMountsFor = mounts;
      serviceConfig.Restart = lib.mkForce "always";
    };
in
{
  sops = {
    secrets = lib.genAttrs stackSecretNames (_: { });

    templates = {
      "clickstack-clickhouse-env".content = ''
        CLICKHOUSE_USER=admin
        CLICKHOUSE_PASSWORD=${config.sops.placeholder."clickhouse-admin-password"}
        CLICKHOUSE_INGEST_PASSWORD=${config.sops.placeholder."clickhouse-ingest-password"}
        CLICKHOUSE_QUERY_PASSWORD=${config.sops.placeholder."clickhouse-query-password"}
      '';
      "clickstack-mongo-env".content = ''
        MONGO_INITDB_ROOT_USERNAME=hyperdx_admin
        MONGO_INITDB_ROOT_PASSWORD=${config.sops.placeholder."mongo-root-password"}
      '';
      "clickstack-collector-env".content = ''
        CLICKHOUSE_ENDPOINT=tcp://clickstack-clickhouse:9000?dial_timeout=10s
        CLICKHOUSE_USER=otel_ingest
        CLICKHOUSE_PASSWORD=${config.sops.placeholder."clickhouse-ingest-password"}
        HYPERDX_OTEL_EXPORTER_CLICKHOUSE_DATABASE=otel
        HYPERDX_OTEL_EXPORTER_CREATE_LEGACY_SCHEMA=true
        HYPERDX_LOG_LEVEL=info
        CUSTOM_OTELCOL_CONFIG_FILE=/etc/otelcol-contrib/homelab.yaml
      '';
      "clickstack-hyperdx-env".content = ''
        EXPRESS_SESSION_SECRET=${config.sops.placeholder."hyperdx-session-secret"}
        HYPERDX_API_KEY=${config.sops.placeholder."hyperdx-api-key"}
        MONGO_URI=mongodb://hyperdx_admin:${
          config.sops.placeholder."mongo-root-password"
        }@clickstack-mongo:27017/hyperdx?authSource=admin
        DEFAULT_CONNECTIONS=[{"name":"Homelab ClickHouse","host":"http://clickstack-clickhouse:8123","username":"hyperdx","password":"${
          config.sops.placeholder."clickhouse-query-password"
        }"}]
        DEFAULT_SOURCES=${builtins.toJSON defaultSources}
      '';
    };
  };

  # These credentials are interpolated into SQL, a MongoDB URI, and JSON
  # environment values. Validate a deliberately narrow alphabet before any
  # consumer starts; never print the values themselves.
  systemd.services.clickstack-secrets-ready = {
    description = "Validate ClickStack secret files";
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    before = stackContainerUnits;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      check_secret() {
        local secret_file="$1"
        local secret_value
        secret_value=$(<"$secret_file")
        if [[ ! "$secret_value" =~ ^[A-Za-z0-9_-]{32,}$ ]]; then
          echo "Refusing an empty or unsafe ClickStack secret file: $secret_file" >&2
          exit 1
        fi
        # $(<file) strips trailing newlines, but sops templates render the raw
        # value; a trailing newline would corrupt env lines and the Mongo URI.
        if [[ $(wc -c <"$secret_file") -ne ''${#secret_value} ]]; then
          echo "Refusing a ClickStack secret with trailing whitespace: $secret_file" >&2
          exit 1
        fi
      }

      ${lib.concatMapStringsSep "\n" (
        name: "check_secret ${lib.escapeShellArg config.sops.secrets.${name}.path}"
      ) stackSecretNames}
    '';
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers = {
      backend = "podman";
      containers = {
        clickstack-clickhouse = {
          image = images.clickhouse;
          autoStart = true;
          environment = {
            CLICKHOUSE_DB = "otel";
            CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT = "1";
          };
          environmentFiles = [ config.sops.templates."clickstack-clickhouse-env".path ];
          volumes = [
            "/var/lib/clickhouse:/var/lib/clickhouse"
            "${clickhouseServerConfig}:/etc/clickhouse-server/config.d/homelab.xml:ro"
            "${clickhouseUsersConfig}:/etc/clickhouse-server/users.d/homelab.xml:ro"
          ];
          extraOptions = [
            "--network=clickstack"
            "--memory=4g"
            "--cpus=3"
            "--pids-limit=1024"
            # Credentials come from CLICKHOUSE_USER/CLICKHOUSE_PASSWORD in the
            # container environment, keeping them out of /proc cmdlines.
            "--health-cmd=clickhouse-client --query 'SELECT 1'"
            "--health-interval=30s"
            "--health-timeout=5s"
            "--health-retries=10"
            "--health-start-period=30s"
          ];
        };

        clickstack-mongo = {
          image = images.mongo;
          autoStart = true;
          environment.MONGO_INITDB_DATABASE = "hyperdx";
          environmentFiles = [ config.sops.templates."clickstack-mongo-env".path ];
          volumes = [ "/var/lib/observability/mongo:/data/db" ];
          extraOptions = [
            "--network=clickstack"
            "--memory=768m"
            "--cpus=1"
            "--pids-limit=512"
            # ping requires no authentication, so no credentials appear in
            # /proc cmdlines. It proves liveness, not credentials; broken
            # auth still surfaces at the HyperDX healthcheck, which logs in
            # with the same root credentials via MONGO_URI.
            "--health-cmd=mongo --quiet --eval 'db.adminCommand({ ping: 1 })'"
            "--health-interval=30s"
            "--health-timeout=10s"
            "--health-retries=10"
            "--health-start-period=30s"
          ];
        };

        clickstack-collector = {
          image = images.collector;
          autoStart = true;
          dependsOn = [ "clickstack-clickhouse" ];
          environmentFiles = [ config.sops.templates."clickstack-collector-env".path ];
          volumes = [
            "${collectorConfig}:/etc/otelcol-contrib/homelab.yaml:ro"
            "/var/lib/clickstack-collector:/var/lib/clickstack-collector"
          ];
          ports = [
            "0.0.0.0:${otlpGrpcPort}:${otlpGrpcPort}"
          ];
          extraOptions = [
            "--network=clickstack"
            "--memory=1280m"
            "--cpus=2"
            "--pids-limit=512"
            "--health-cmd=wget -q --spider http://127.0.0.1:13133/ || exit 1"
            "--health-interval=30s"
            "--health-timeout=5s"
            "--health-retries=10"
            "--health-start-period=30s"
          ];
        };

        clickstack-hyperdx = {
          image = images.hyperdx;
          autoStart = true;
          dependsOn = [
            "clickstack-clickhouse"
            "clickstack-mongo"
            "clickstack-collector"
          ];
          environment = {
            FRONTEND_URL = hyperdxFrontendUrl;
            HYPERDX_API_PORT = "8000";
            HYPERDX_APP_PORT = hyperdxPort;
            HYPERDX_APP_URL = hyperdxFrontendUrl;
            HYPERDX_LOG_LEVEL = "info";
            OTEL_EXPORTER_OTLP_ENDPOINT = "http://clickstack-collector:4318";
            OTEL_SERVICE_NAME = "clickstack-hyperdx";
            SERVER_URL = "http://127.0.0.1:8000";
            USAGE_STATS_ENABLED = "false";
          };
          environmentFiles = [ config.sops.templates."clickstack-hyperdx-env".path ];
          ports = [
            "0.0.0.0:${hyperdxPort}:${hyperdxPort}"
          ];
          extraOptions = [
            "--network=clickstack"
            "--memory=1280m"
            "--cpus=2"
            "--pids-limit=768"
            "--health-cmd=node -e \"require('http').get('http://127.0.0.1:8000/health',r=>r.statusCode===200?process.exit(0):process.exit(1)).on('error',()=>process.exit(1))\""
            "--health-interval=30s"
            "--health-timeout=5s"
            "--health-retries=10"
            "--health-start-period=45s"
          ];
        };
      };
    };
  };

  systemd.services.podman-network-clickstack = {
    description = "Create private ClickStack Podman network";
    wantedBy = [ "multi-user.target" ];
    before = stackContainerUnits;
    after = [ "var-lib-containers.mount" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/containers" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists clickstack || \
        ${pkgs.podman}/bin/podman network create clickstack
    '';
  };

  systemd.services.clickstack-databases-ready = {
    description = "Wait for private ClickStack databases";
    after = map containerUnit [
      "clickhouse"
      "mongo"
    ];
    requires = map containerUnit [
      "clickhouse"
      "mongo"
    ];
    before = map containerUnit [
      "collector"
      "hyperdx"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      for _ in $(seq 1 90); do
        if ${pkgs.podman}/bin/podman healthcheck run clickstack-clickhouse >/dev/null 2>&1 && \
           ${pkgs.podman}/bin/podman healthcheck run clickstack-mongo >/dev/null 2>&1; then
          exit 0
        fi
        sleep 2
      done
      echo "ClickStack databases did not become healthy" >&2
      exit 1
    '';
  };

  # Provision the otel_ingest / hyperdx SQL users idempotently on every start,
  # after ClickHouse is healthy and before the collector/HyperDX connect.
  # Replaces the first-boot-only initdb script, which never ran (Nix-store
  # shebang absent in the Alpine image) and would never re-run on a populated
  # data dir. The script is fed to the container shell over stdin so the
  # credentials expand from the container env, never a host argv or the store.
  systemd.services.clickstack-users-ready = {
    description = "Provision ClickStack ClickHouse users";
    after = [ "clickstack-databases-ready.service" ];
    requires = [ "clickstack-databases-ready.service" ];
    before = map containerUnit [
      "collector"
      "hyperdx"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      for _ in $(seq 1 10); do
        if ${pkgs.podman}/bin/podman exec -i clickstack-clickhouse sh < ${clickhouseUsersScript}; then
          exit 0
        fi
        echo "ClickStack user provisioning failed; retrying" >&2
        sleep 3
      done
      echo "ClickStack user provisioning did not succeed" >&2
      exit 1
    '';
  };

  systemd.services.podman-clickstack-clickhouse = mkContainerService {
    after = [
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    requires = [
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    mounts = [
      "/var/lib/clickhouse"
      "/var/lib/containers"
    ];
  };
  systemd.services.podman-clickstack-mongo = mkContainerService {
    after = [
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    requires = [
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    mounts = [
      "/var/lib/observability"
      "/var/lib/containers"
    ];
  };
  systemd.services.podman-clickstack-collector = mkContainerService {
    after = [
      "clickstack-users-ready.service"
      "clickstack-databases-ready.service"
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    requires = [
      "clickstack-users-ready.service"
      "clickstack-databases-ready.service"
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    mounts = [
      "/var/lib/clickstack-collector"
      "/var/lib/containers"
    ];
  };
  systemd.services.podman-clickstack-hyperdx = mkContainerService {
    after = [
      "clickstack-users-ready.service"
      "clickstack-databases-ready.service"
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    requires = [
      "clickstack-users-ready.service"
      "clickstack-databases-ready.service"
      "podman-network-clickstack.service"
      "clickstack-secrets-ready.service"
    ];
    mounts = [ "/var/lib/containers" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/observability/mongo 0750 999 999 -"
    "d /var/lib/clickstack-collector/queue 0750 10001 10001 -"
    "d /var/lib/clickstack-collector/compaction 0750 10001 10001 -"
    "d /var/lib/observability-backup/clickhouse 0755 root root -"
    "d /var/lib/observability-backup/mongo 0755 root root -"
  ];

  # Daily application-consistent backups to the ocean-backed share — the
  # second failure domain for the only copy of central history. Retention
  # lives here (7 daily ClickHouse backups, 14 Mongo archives); ocean-side
  # snapshots are a later decision.
  systemd.services.observability-clickhouse-backup = {
    description = "Daily ClickHouse-native backup to ocean";
    after = [ "podman-clickstack-clickhouse.service" ];
    requires = [ "podman-clickstack-clickhouse.service" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/observability-backup" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "2h";
    };
    path = [
      pkgs.podman
      pkgs.coreutils
      pkgs.findutils
    ];
    script = ''
      set -euo pipefail
      stamp=$(date +%F-%H%M%S)
      # clickhouse-client authenticates from the container environment. The
      # backup stages on the zvol, then guest root moves it to the share —
      # the server never writes through virtiofs.
      podman exec clickstack-clickhouse clickhouse-client \
        --query "BACKUP DATABASE otel TO Disk('backups', '$stamp')"
      mv "/var/lib/clickhouse/backups/$stamp" \
        "/var/lib/observability-backup/clickhouse/$stamp"
      # Sweep any staging leftovers from failed prior runs.
      find /var/lib/clickhouse/backups -mindepth 1 -maxdepth 1 \
        -mtime +1 -exec rm -rf {} +
      find /var/lib/observability-backup/clickhouse \
        -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} +
    '';
  };
  systemd.timers.observability-clickhouse-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:15:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  systemd.services.observability-mongo-backup = {
    description = "Daily MongoDB dump to ocean";
    after = [ "podman-clickstack-mongo.service" ];
    requires = [ "podman-clickstack-mongo.service" ];
    unitConfig.RequiresMountsFor = [ "/var/lib/observability-backup" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "30m";
    };
    path = [
      pkgs.podman
      pkgs.coreutils
      pkgs.findutils
    ];
    script = ''
      set -euo pipefail
      stamp=$(date +%F-%H%M%S)
      # Password travels via a process-substitution config file, not argv.
      podman exec clickstack-mongo bash -c \
        'mongodump --quiet --archive --gzip --authenticationDatabase admin -u "$MONGO_INITDB_ROOT_USERNAME" --config <(printf "password: %s\n" "$MONGO_INITDB_ROOT_PASSWORD")' \
        > "/var/lib/observability-backup/mongo/$stamp.archive.gz"
      find /var/lib/observability-backup/mongo \
        -mindepth 1 -maxdepth 1 -mtime +14 -delete
    '';
  };
  systemd.timers.observability-mongo-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:45:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}
