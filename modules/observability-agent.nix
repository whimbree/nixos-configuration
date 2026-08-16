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
      description = "Collector memory-limiter ceiling in MiB.";
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
    ];

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
        # The limiter tracks Go heap only; process RSS (stacks, GC headroom,
        # bbolt mmap) runs well above it. Keep the cgroup at 1.5x the limiter
        # so a burst hits soft backpressure before an OOM kill.
        MemoryMax = "${toString (cfg.memoryLimitMiB * 3 / 2)}M";
        SupplementaryGroups = lib.mkAfter cfg.supplementaryGroups;
      };
    };
  };
}
