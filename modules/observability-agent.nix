{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.homelab.observabilityAgent;

  # node_exporter's textfile collector is deliberately used as the bridge for
  # these Linux-specific signals. The OpenTelemetry hostmetrics receiver
  # exposes whole-node CPU, memory, paging, and filesystem data, but it does
  # not expose the collector service's cgroup-v2 memory.events, memory.stat,
  # or PSI files. Those are the authoritative signals for the failure mode
  # that caused the August 2026 fleet-wide reclaim storm.
  #
  # Event, reclaim, fault, pressure, and swap-I/O values are exported as
  # cumulative counters. A badly thrashing collector may be too starved to
  # scrape or export during the incident itself; once it recovers, the next
  # scrape still observes the counter increase. Alerts should therefore use
  # rates/deltas rather than absolute counter values, which also handles the
  # normal reset when a service cgroup or node restarts.
  #
  # Physical-host configurations retain node_exporter's normal system metrics
  # and any explicitly enabled hardware/systemd collectors. On MicroVMs the
  # configuration below enables only its textfile collector, so detecting this
  # failure does not add a second full host-metrics pipeline beside hostmetrics.
  thrashMetricsDirectory = "/var/lib/observability-thrash-metrics";
  thrashMetricsWriter = pkgs.writeShellApplication {
    name = "write-observability-thrash-metrics";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail
      umask 022

      if [[ -z "''${STATE_DIRECTORY:-}" ]]; then
        echo "STATE_DIRECTORY is not set" >&2
        exit 1
      fi

      output="$STATE_DIRECTORY/.collector-thrash.prom.tmp"

      read_number() {
        local value
        value=$(<"$1")
        if [[ "$value" == "max" ]]; then
          # Prometheus gauges must be numeric. -1 consistently represents an
          # unlimited cgroup control value; deployed configurations use finite
          # limits, but retaining this case keeps the exporter honest during
          # emergency runtime overrides.
          printf '%s\n' -1
        else
          printf '%s\n' "$value"
        fi
      }

      emit_pressure() {
        local metric=$1
        local resource=$2
        local pressure_file=$3
        local scope
        local field
        local total_us

        [[ -r "$pressure_file" ]] || return 0
        while read -r scope fields; do
          [[ "$scope" == "some" || "$scope" == "full" ]] || continue
          total_us=0
          for field in $fields; do
            if [[ "$field" == total=* ]]; then
              total_us=''${field#total=}
              break
            fi
          done
          # PSI reports cumulative microseconds. Render seconds without
          # spawning awk: this sampler runs fleet-wide, and avoiding repeated
          # executable faults is part of keeping the monitor cheaper than the
          # failure it is intended to detect.
          printf '%s{resource="%s",scope="%s"} %d.%06d\n' \
            "$metric" "$resource" "$scope" \
            "$((total_us / 1000000))" "$((total_us % 1000000))"
        done < "$pressure_file"
      }

      collector_cgroup=$(systemctl show opentelemetry-collector.service \
        --property=ControlGroup --value 2>/dev/null || true)
      collector_cgroup_dir="/sys/fs/cgroup$collector_cgroup"

      # Parse each kernel pseudo-file once into Bash associative arrays. The
      # first implementation launched awk separately for every key, which was
      # needless process/page-cache churn on small guests and ran more often
      # than the Prometheus scrape. These files are already line-oriented
      # key/value data and do not need external parsers.
      declare -A system_meminfo_kib=()
      while read -r key value _unit; do
        key=''${key%:}
        system_meminfo_kib["$key"]=$value
      done < /proc/meminfo

      declare -A system_vmstat=()
      while read -r key value; do
        system_vmstat["$key"]=$value
      done < /proc/vmstat

      {
        cat <<'METADATA'
      # HELP homelab_otelcol_cgroup_metrics_up Whether the collector cgroup was present when sampled.
      # TYPE homelab_otelcol_cgroup_metrics_up gauge
      # HELP homelab_otelcol_cgroup_memory_bytes Collector cgroup memory by kind. A limit of -1 means unlimited.
      # TYPE homelab_otelcol_cgroup_memory_bytes gauge
      # HELP homelab_otelcol_cgroup_swap_bytes Collector cgroup swap by kind. A limit of -1 means unlimited.
      # TYPE homelab_otelcol_cgroup_swap_bytes gauge
      # HELP homelab_otelcol_cgroup_memory_events_total Collector cgroup memory boundary events since cgroup creation.
      # TYPE homelab_otelcol_cgroup_memory_events_total counter
      # HELP homelab_otelcol_cgroup_swap_events_total Collector cgroup swap boundary events since cgroup creation.
      # TYPE homelab_otelcol_cgroup_swap_events_total counter
      # HELP homelab_otelcol_cgroup_reclaim_pages_total Collector cgroup pages scanned or reclaimed since cgroup creation.
      # TYPE homelab_otelcol_cgroup_reclaim_pages_total counter
      # HELP homelab_otelcol_cgroup_direct_reclaim_pages_total Collector cgroup pages scanned or reclaimed by direct reclaim since cgroup creation.
      # TYPE homelab_otelcol_cgroup_direct_reclaim_pages_total counter
      # HELP homelab_otelcol_cgroup_workingset_pages_total Collector cgroup file-cache refault/activation events since cgroup creation.
      # TYPE homelab_otelcol_cgroup_workingset_pages_total counter
      # HELP homelab_otelcol_cgroup_faults_total Collector cgroup page faults since cgroup creation.
      # TYPE homelab_otelcol_cgroup_faults_total counter
      # HELP homelab_otelcol_cgroup_pressure_stall_seconds_total Time collector work was delayed by cgroup resource pressure.
      # TYPE homelab_otelcol_cgroup_pressure_stall_seconds_total counter
      # HELP homelab_system_pressure_stall_seconds_total Time node work was delayed by whole-system resource pressure.
      # TYPE homelab_system_pressure_stall_seconds_total counter
      # HELP homelab_system_swap_bytes Whole-node swap capacity by kind.
      # TYPE homelab_system_swap_bytes gauge
      # HELP homelab_system_swap_io_pages_total Whole-node pages swapped in or out since boot.
      # TYPE homelab_system_swap_io_pages_total counter
      METADATA

        # Swap occupancy is not itself evidence of thrashing: cold pages can
        # remain in swap indefinitely after a transient event. Alert on the
        # rate of pswpin/pswpout together with memory PSI instead. That detects
        # active swap churn without paging operators merely because a long-lived
        # host has non-zero swap usage.
        swap_total_kib=''${system_meminfo_kib[SwapTotal]:-0}
        swap_free_kib=''${system_meminfo_kib[SwapFree]:-0}
        swap_total=$((swap_total_kib * 1024))
        swap_free=$((swap_free_kib * 1024))
        printf 'homelab_system_swap_bytes{kind="total"} %s\n' "$swap_total"
        printf 'homelab_system_swap_bytes{kind="free"} %s\n' "$swap_free"
        printf 'homelab_system_swap_bytes{kind="used"} %s\n' "$((swap_total - swap_free))"
        printf 'homelab_system_swap_io_pages_total{direction="in"} %s\n' \
          "''${system_vmstat[pswpin]:-0}"
        printf 'homelab_system_swap_io_pages_total{direction="out"} %s\n' \
          "''${system_vmstat[pswpout]:-0}"

        for resource in cpu memory io; do
          emit_pressure homelab_system_pressure_stall_seconds_total \
            "$resource" "/proc/pressure/$resource"
        done

        if [[ -n "$collector_cgroup" && "$collector_cgroup" != "/" && -r "$collector_cgroup_dir/memory.current" ]]; then
          declare -A cgroup_memory_stat=()
          while read -r key value; do
            cgroup_memory_stat["$key"]=$value
          done < "$collector_cgroup_dir/memory.stat"

          printf 'homelab_otelcol_cgroup_metrics_up 1\n'
          printf 'homelab_otelcol_cgroup_memory_bytes{kind="current"} %s\n' \
            "$(read_number "$collector_cgroup_dir/memory.current")"
          printf 'homelab_otelcol_cgroup_memory_bytes{kind="high"} %s\n' \
            "$(read_number "$collector_cgroup_dir/memory.high")"
          printf 'homelab_otelcol_cgroup_memory_bytes{kind="max"} %s\n' \
            "$(read_number "$collector_cgroup_dir/memory.max")"
          printf 'homelab_otelcol_cgroup_memory_bytes{kind="anon"} %s\n' \
            "''${cgroup_memory_stat[anon]:-0}"
          printf 'homelab_otelcol_cgroup_memory_bytes{kind="file"} %s\n' \
            "''${cgroup_memory_stat[file]:-0}"

          if [[ -r "$collector_cgroup_dir/memory.swap.current" ]]; then
            printf 'homelab_otelcol_cgroup_swap_bytes{kind="current"} %s\n' \
              "$(read_number "$collector_cgroup_dir/memory.swap.current")"
            printf 'homelab_otelcol_cgroup_swap_bytes{kind="high"} %s\n' \
              "$(read_number "$collector_cgroup_dir/memory.swap.high")"
            printf 'homelab_otelcol_cgroup_swap_bytes{kind="max"} %s\n' \
              "$(read_number "$collector_cgroup_dir/memory.swap.max")"
          fi

          while read -r event value; do
            printf 'homelab_otelcol_cgroup_memory_events_total{event="%s"} %s\n' "$event" "$value"
          done < "$collector_cgroup_dir/memory.events"

          if [[ -r "$collector_cgroup_dir/memory.swap.events" ]]; then
            while read -r event value; do
              printf 'homelab_otelcol_cgroup_swap_events_total{event="%s"} %s\n' "$event" "$value"
            done < "$collector_cgroup_dir/memory.swap.events"
          fi

          printf 'homelab_otelcol_cgroup_reclaim_pages_total{operation="scan"} %s\n' \
            "''${cgroup_memory_stat[pgscan]:-0}"
          printf 'homelab_otelcol_cgroup_reclaim_pages_total{operation="steal"} %s\n' \
            "''${cgroup_memory_stat[pgsteal]:-0}"
          printf 'homelab_otelcol_cgroup_direct_reclaim_pages_total{operation="scan"} %s\n' \
            "''${cgroup_memory_stat[pgscan_direct]:-0}"
          printf 'homelab_otelcol_cgroup_direct_reclaim_pages_total{operation="steal"} %s\n' \
            "''${cgroup_memory_stat[pgsteal_direct]:-0}"
          # workingset_refault_file is the most specific signature of the
          # incident we observed: file-backed EROFS/journal pages were evicted
          # to satisfy the cgroup limit and immediately needed again. Aggregate
          # pgscan alone cannot distinguish that loop from useful reclaim.
          printf 'homelab_otelcol_cgroup_workingset_pages_total{event="refault_file"} %s\n' \
            "''${cgroup_memory_stat[workingset_refault_file]:-0}"
          printf 'homelab_otelcol_cgroup_workingset_pages_total{event="activate_file"} %s\n' \
            "''${cgroup_memory_stat[workingset_activate_file]:-0}"
          printf 'homelab_otelcol_cgroup_faults_total{kind="all"} %s\n' \
            "''${cgroup_memory_stat[pgfault]:-0}"
          printf 'homelab_otelcol_cgroup_faults_total{kind="major"} %s\n' \
            "''${cgroup_memory_stat[pgmajfault]:-0}"

          for resource in cpu memory io; do
            emit_pressure homelab_otelcol_cgroup_pressure_stall_seconds_total \
              "$resource" "$collector_cgroup_dir/$resource.pressure"
          done
        else
          # Keep a positive, scrapeable indication of the missing cgroup. A
          # vanished series is ambiguous (agent, exporter, or network); up=0
          # specifically says the sampler ran but the collector cgroup did not.
          printf 'homelab_otelcol_cgroup_metrics_up 0\n'
        fi
      } > "$output"

      chmod 0644 "$output"
      mv -f "$output" "$STATE_DIRECTORY/collector-thrash.prom"
    '';
  };

  fileReceiverNames = map (name: "filelog/${name}") (builtins.attrNames cfg.fileLogs);
  fileReceivers = lib.mapAttrs' (
    name: fileLog:
    lib.nameValuePair "filelog/${name}" (
      {
        inherit (fileLog) include;
        resource."service.name" = fileLog.serviceName;
        start_at = fileLog.startAt;
        storage = "file_storage";
        include_file_path = true;
        retry_on_failure = {
          enabled = true;
          max_elapsed_time = "0s";
        };
      }
      // lib.optionalAttrs (fileLog.exclude != [ ]) {
        inherit (fileLog) exclude;
      }
      // lib.optionalAttrs (fileLog.operators != [ ]) {
        inherit (fileLog) operators;
      }
    )
  ) cfg.fileLogs;
  resourceAttributes = [
    {
      key = "host.name";
      value = config.networking.hostName;
      action = "upsert";
    }
    {
      key = "deployment.environment.name";
      value = "homelab";
      action = "upsert";
    }
    {
      key = "homelab.node.kind";
      value = cfg.nodeKind;
      action = "upsert";
    }
    {
      # nixpkgs release + input revision, e.g. 26.11.20260813.0e251e2 —
      # identifies the OS build every record was produced under.
      key = "homelab.nixos.version";
      value = config.system.nixos.version;
      action = "upsert";
    }
    {
      key = "service.name";
      value = "node-telemetry";
      action = "insert";
    }
  ]
  ++ lib.optionals (config.system.configurationRevision != null) [
    {
      # Config-repo commit (physical hosts only; see flake.nix for why
      # MicroVMs omit it). A -dirty suffix exposes uncommitted deploys.
      key = "homelab.config.revision";
      value = config.system.configurationRevision;
      action = "upsert";
    }
  ]
  ++ lib.optionals (cfg.tier != null) [
    {
      key = "homelab.microvm.tier";
      value = toString cfg.tier;
      action = "upsert";
    }
  ]
  ++ lib.optionals (cfg.hypervisor != null) [
    {
      key = "homelab.hypervisor";
      value = cfg.hypervisor;
      action = "upsert";
    }
  ]
  ++ lib.optionals (cfg.ipAddress != null) [
    {
      key = "homelab.node.ip";
      value = cfg.ipAddress;
      action = "upsert";
    }
  ];
in
{
  options.homelab.observabilityAgent = {
    enable = mkEnableOption "durable homelab OpenTelemetry agent";

    endpoint = mkOption {
      type = types.str;
      description = "Private OTLP/gRPC endpoint for the central ClickStack collector.";
    };

    nodeKind = mkOption {
      type = types.enum [
        "host"
        "microvm"
      ];
      description = "Stable resource classification for this telemetry producer.";
    };

    tier = mkOption {
      type = types.nullOr types.int;
      default = null;
      description = "MicroVM trust tier, when the producer is a MicroVM.";
    };

    hypervisor = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Hypervisor host name, when the producer is a MicroVM.";
    };

    ipAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Stable primary IP of this producer, when declaratively known (set
        from the VM registry for MicroVMs). Lets searches resolve an address
        seen in a log line to its node.
      '';
    };

    journalMaxUse = mkOption {
      type = types.str;
      default = "6G";
      description = "Bound for persistent systemd journal storage.";
    };

    queueMaxMiB = mkOption {
      type = types.ints.positive;
      default = 1024;
      description = ''
        On-disk byte ceiling for each signal's persistent OTLP exporter
        queue, in MiB. The logs and metrics pipelines get independent queues
        of this size, so worst-case disk use is twice this value.
      '';
    };

    memoryLimitMiB = mkOption {
      type = types.ints.positive;
      default = 256;
      description = ''
        OpenTelemetry memory_limiter hard threshold in MiB. This targets the
        process heap and controls receiver backpressure/forced Go garbage
        collection; it is not the systemd cgroup's total-memory allowance.
      '';
    };

    memoryMaxMiB = mkOption {
      type = types.ints.positive;
      default = 1024;
      description = ''
        Emergency systemd cgroup-v2 MemoryMax threshold in MiB. It bounds
        resident cgroup memory but must not be sized from the OpenTelemetry
        heap threshold alone because cgroups also charge executable mappings,
        stacks, kernel memory, bbolt mappings, and file-backed page cache.
        MemoryMax is a ceiling, not a reservation.
      '';
    };

    memorySwapMaxMiB = mkOption {
      type = types.ints.unsigned;
      default = 0;
      description = ''
        systemd cgroup-v2 MemorySwapMax threshold in MiB. memory.max does not
        include swap, so a separate finite limit is required to prevent a
        collector on a swap-enabled physical host from replacing resident
        anonymous pages with sustained swap I/O. Zero keeps this
        latency-sensitive service out of swap; durable exporter queues provide
        safer backpressure and recovery than swapping the collector itself.
      '';
    };

    fileLogs = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            include = mkOption {
              type = types.nonEmptyListOf types.str;
              description = "File globs read by this receiver.";
            };

            exclude = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Optional file globs excluded from this receiver.";
            };

            serviceName = mkOption {
              type = types.str;
              description = "OpenTelemetry service.name assigned to matching logs.";
            };

            startAt = mkOption {
              type = types.enum [
                "beginning"
                "end"
              ];
              default = "end";
              description = "Where to begin when no durable file cursor exists.";
            };

            operators = mkOption {
              type = types.listOf types.attrs;
              default = [ ];
              description = ''
                stanza operators run by this receiver, e.g. a json_parser to
                turn structured access logs into typed attributes.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Additional application log files. Attribute names become collector
        receiver IDs such as `filelog/nginx`; storage and retry behavior are
        generated consistently by this module.
      '';
    };

    supplementaryGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Groups needed to read explicitly configured application logs.";
    };

    prometheusScrapes = mkOption {
      type = types.attrsOf types.port;
      default = { };
      description = ''
        Extra localhost Prometheus endpoints scraped into the metrics
        pipeline, name to port (for example node/zfs/smartctl/ipmi
        exporters on physical hosts).
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (name: builtins.match "[A-Za-z0-9_-]+" name != null) (
          builtins.attrNames cfg.fileLogs
        );
        message = "homelab.observabilityAgent.fileLogs names may contain only letters, numbers, underscores, and hyphens";
      }
      {
        assertion = cfg.memoryMaxMiB > cfg.memoryLimitMiB;
        message = ''
          homelab.observabilityAgent.memoryMaxMiB must exceed
          memoryLimitMiB so non-heap cgroup memory has explicit headroom.
        '';
      }
    ];

    # Export the targeted cgroup/PSI/swap metrics through the same localhost
    # Prometheus path as the agent's existing self-metrics. On MicroVMs,
    # disable node_exporter's default collector set: hostmetrics already owns
    # those signals, and duplicating hundreds of series per VM would add cost
    # while trying to monitor a resource incident. Physical hosts retain their
    # existing default and explicitly enabled collectors.
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = lib.mkDefault "127.0.0.1";
      enabledCollectors = [ "textfile" ];
      extraFlags = [
        "--collector.textfile.directory=${thrashMetricsDirectory}"
      ]
      ++ lib.optionals (cfg.nodeKind == "microvm") [ "--collector.disable-defaults" ];
    };

    homelab.observabilityAgent.prometheusScrapes.node = lib.mkDefault 9100;

    systemd.services = {
      observability-thrash-metrics = {
        description = "Snapshot OpenTelemetry cgroup and system thrash metrics";
        after = [ "opentelemetry-collector.service" ];
        before = [ "prometheus-node-exporter.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${thrashMetricsWriter}/bin/write-observability-thrash-metrics";
          StateDirectory = "observability-thrash-metrics";
          StateDirectoryMode = "0755";
          UMask = "0022";
          Nice = 10;
          CPUWeight = 10;
          IOSchedulingClass = "idle";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };

      prometheus-node-exporter.after = [ "observability-thrash-metrics.service" ];
    };

    systemd.timers.observability-thrash-metrics = {
      description = "Refresh OpenTelemetry cgroup and system thrash metrics";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15s";
        # Match the Prometheus receiver's 30-second scrape cadence. All event,
        # reclaim, PSI, and swap-I/O signals are cumulative, so a burst remains
        # detectable even if it begins and ends between samples; sampling more
        # frequently would only add fleet-wide process wakeups.
        OnUnitActiveSec = "30s";
        RandomizedDelaySec = "5s";
        AccuracySec = "1s";
        Unit = "observability-thrash-metrics.service";
      };
    };

    services.journald.extraConfig = lib.mkAfter ''
      Storage=persistent
      SystemMaxUse=${cfg.journalMaxUse}
      MaxRetentionSec=1month
    '';

    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;
      validateConfigFile = true;
      settings = {
        extensions.file_storage = {
          directory = "/var/log/observability-agent/storage";
          create_directory = true;
          fsync = true;
          recreate = false;
          compaction = {
            on_start = true;
            on_rebound = true;
            directory = "/var/log/observability-agent/compaction";
            cleanup_on_start = true;
          };
        };

        receivers = {
          journald = {
            directory = "/var/log/journal";
            start_at = "end";
            priority = "debug";
            all = true;
            storage = "file_storage";
            retry_on_failure = {
              enabled = true;
              initial_interval = "1s";
              max_interval = "30s";
              max_elapsed_time = "0s";
            };
            # The journald receiver emits the whole journal record as a body
            # map and sets no attributes and no severity. Map PRIORITY here so
            # kernel/service errors are not stored as "info"; identity fields
            # are copied out of the body by transform/normalize below.
            operators = [
              {
                type = "severity_parser";
                parse_from = "body.PRIORITY";
                on_error = "send_quiet";
                mapping = {
                  debug = "7";
                  info = [
                    "6"
                    "5"
                  ];
                  warn = "4";
                  error = "3";
                  fatal = [
                    "2"
                    "1"
                    "0"
                  ];
                };
              }
            ];
          };

          hostmetrics = {
            collection_interval = "30s";
            scrapers = {
              cpu = { };
              load.cpu_average = true;
              memory = { };
              paging = { };
              # Aggregate process counts only (running/zombie/created) —
              # catches fork storms and zombie leaks without the cardinality
              # and privileges of the per-process scraper.
              processes = { };
              # system.uptime: makes unexpected reboots visible as data.
              system = { };
              disk.exclude = {
                devices = [ "^(loop|ram|zram|fd|sr)[0-9]+$" ];
                match_type = "regexp";
              };
              filesystem = {
                include_virtual_filesystems = false;
                exclude_fs_types = {
                  fs_types = [
                    "autofs"
                    "binfmt_misc"
                    "bpf"
                    "cgroup"
                    "cgroup2"
                    "configfs"
                    "debugfs"
                    "devpts"
                    "devtmpfs"
                    "fusectl"
                    "hugetlbfs"
                    "mqueue"
                    "nsfs"
                    "proc"
                    "pstore"
                    "securityfs"
                    "sysfs"
                    "tracefs"
                  ];
                  match_type = "strict";
                };
              };
              network.exclude = {
                interfaces = [ "^(lo|veth.*|podman.*|cni.*)$" ];
                match_type = "regexp";
              };
            };
          };
          # The agent's own health — above all persistent-queue depth — must
          # be visible centrally: queue-full drops newest records silently,
          # and the log filter (deliberately) hides agent errors from export.
          # Scraping our own telemetry endpoint closes that gap; hosts add
          # their hardware/ZFS exporters through prometheusScrapes.
          prometheus.config.scrape_configs = [
            {
              job_name = "observability-agent";
              scrape_interval = "30s";
              static_configs = [ { targets = [ "127.0.0.1:8888" ]; } ];
            }
          ]
          ++ lib.mapAttrsToList (name: port: {
            job_name = name;
            scrape_interval = "30s";
            static_configs = [ { targets = [ "127.0.0.1:${toString port}" ]; } ];
          }) cfg.prometheusScrapes;
        }
        // fileReceivers;

        processors = {
          memory_limiter = {
            check_interval = "5s";
            limit_mib = cfg.memoryLimitMiB;
            spike_limit_mib = lib.max 1 (cfg.memoryLimitMiB / 4);
          };

          # A collector exporting its own exporter failures back through the
          # same unavailable endpoint creates a positive feedback loop. Keep
          # collector diagnostics in the local journal, but do not re-ingest
          # native-agent or central-collector container output. This runs
          # before transform/normalize, while journald fields are still in
          # the body map.
          "filter/drop-exporter-feedback" = {
            error_mode = "ignore";
            logs.log_record = [
              ''IsMap(body) and body["_SYSTEMD_UNIT"] == "opentelemetry-collector.service"''
              ''IsMap(body) and body["CONTAINER_NAME"] == "clickstack-collector"''
            ];
          };

          "resource/node".attributes = resourceAttributes;

          # Drop known credential-bearing attributes before they leave a node.
          # Message bodies remain intact; source-specific body redaction is added
          # only when a real producer format is known and testable.
          "attributes/redact".actions = [
            {
              pattern = "(?i)^(authorization|proxy-authorization|cookie|set-cookie|.*password.*|.*passwd.*|.*token.*|.*secret.*|.*api[_-]?key.*)$";
              action = "delete";
            }
          ];

          # The journald receiver keeps every field in the body map. Copy the
          # stable systemd/Podman identities to record attributes, then flatten
          # the body to the human-readable message so the central collector
          # does not double-store ~25 metadata fields per record. All journald
          # records in a converter batch share one resource, so per-record
          # resource writes are unsafe here; groupbyattrs regroups service.name
          # into correct per-service resources afterwards.
          "transform/normalize" = {
            error_mode = "ignore";
            log_statements = [
              {
                context = "log";
                statements = [
                  ''set(attributes["systemd.unit"], body["_SYSTEMD_UNIT"]) where IsMap(body) and body["_SYSTEMD_UNIT"] != nil''
                  ''set(attributes["service.name"], body["_SYSTEMD_UNIT"]) where IsMap(body) and body["_SYSTEMD_UNIT"] != nil''
                  ''set(attributes["service.name"], body["SYSLOG_IDENTIFIER"]) where IsMap(body) and body["SYSLOG_IDENTIFIER"] != nil''
                  ''set(attributes["container.name"], body["CONTAINER_NAME"]) where IsMap(body) and body["CONTAINER_NAME"] != nil''
                  ''set(attributes["container.id"], body["CONTAINER_ID_FULL"]) where IsMap(body) and body["CONTAINER_ID_FULL"] != nil''
                  ''set(attributes["process.pid"], body["_PID"]) where IsMap(body) and body["_PID"] != nil''
                  ''set(body, body["MESSAGE"]) where IsMap(body) and body["MESSAGE"] != nil''
                ];
              }
            ];
          };

          # Move each record's service.name to its resource so HyperDX's
          # ServiceName column is correct per record instead of one shared
          # value per receiver batch. Records without the attribute (for
          # example filelog entries, whose receivers set a resource-level
          # service.name already) keep their original resource.
          groupbyattrs.keys = [ "service.name" ];

          batch = {
            send_batch_size = 2048;
            send_batch_max_size = 4096;
            timeout = "5s";
          };
        };

        exporters.otlp = {
          endpoint = cfg.endpoint;
          tls.insecure = true;
          sending_queue = {
            enabled = true;
            num_consumers = 4;
            # Byte-bounded so a multi-day central outage cannot overrun the
            # volume that also holds the journal; request counts alone say
            # nothing about disk growth.
            sizer = "bytes";
            queue_size = cfg.queueMaxMiB * 1024 * 1024;
            storage = "file_storage";
          };
          retry_on_failure = {
            enabled = true;
            initial_interval = "1s";
            max_interval = "30s";
            max_elapsed_time = "0s";
          };
        };

        service = {
          extensions = [ "file_storage" ];
          pipelines = {
            logs = {
              receivers = [ "journald" ] ++ fileReceiverNames;
              processors = [
                "memory_limiter"
                "filter/drop-exporter-feedback"
                "transform/normalize"
                "attributes/redact"
                "resource/node"
                "groupbyattrs"
                "batch"
              ];
              exporters = [ "otlp" ];
            };
            metrics = {
              receivers = [
                "hostmetrics"
                "prometheus"
              ];
              processors = [
                "memory_limiter"
                "resource/node"
                "batch"
              ];
              exporters = [ "otlp" ];
            };
          };
          telemetry = {
            logs.level = "info";
            metrics.readers = [
              {
                pull.exporter.prometheus = {
                  host = "127.0.0.1";
                  port = 8888;
                };
              }
            ];
          };
        };
      };
    };

    systemd.services.opentelemetry-collector = {
      after = [
        "network-online.target"
        "var-log.mount"
      ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ "/var/log" ];
      serviceConfig = {
        LogsDirectory = "observability-agent";
        # memory_limiter's limit_mib targets the Collector heap. In contrast,
        # cgroup-v2 MemoryCurrent/Max charge the entire resident working set,
        # including file-backed pages from the journal, application logs,
        # persistent queue, executable/libraries, and the EROFS Nix store.
        #
        # Deriving MemoryMax as 1.5x the heap threshold left MicroVM agents only
        # 192 MiB for a measured 335-380 MiB working set. The kernel then
        # evicted and immediately refaulted the same EROFS/journal pages millions
        # of times across the fleet. That reclaim storm saturated Bastion even
        # though every guest had ample total RAM and no OOM kills. Keep the heap
        # backpressure threshold independent from the hard cgroup ceiling.
        #
        # MemoryHigh is intentionally left at infinity. Despite its name, it is
        # not an alert-only threshold: crossing it makes the kernel throttle
        # allocations and force reclaim. Placing it near the normal working set
        # would recreate the same eviction/refault loop below MemoryMax. The
        # Collector's memory_limiter supplies application-aware backpressure;
        # the cgroup metrics above provide early warning without inducing
        # reclaim. MemoryMax remains the last-resort containment boundary.
        #
        # memory.max does not account for swapped-out anonymous pages, so
        # MemorySwapMax is a separate requirement on physical hosts with swap
        # and zswap. Keeping the Collector unswappable prevents telemetry from
        # driving swap churn; its durable queue can absorb downstream outages.
        # Neither cgroup setting reserves memory.
        MemoryMax = "${toString cfg.memoryMaxMiB}M";
        MemorySwapMax = "${toString cfg.memorySwapMaxMiB}M";
        SupplementaryGroups = lib.mkAfter cfg.supplementaryGroups;
      };
    };
  };
}
