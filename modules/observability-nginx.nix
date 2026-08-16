# Structured nginx access logging for observability producers.
#
# nginx writes access logs as one JSON object per request; the agent's filelog
# receiver parses that into typed attributes (status, host, method, uri, url,
# request_time, upstream, request_id, ...) so HyperDX/ClickHouse can facet and
# aggregate on them instead of substring-matching a text line. Import on any
# nginx host that also runs the observability agent.
{ lib, ... }:
{
  services.nginx.logError = lib.mkDefault "/var/log/nginx/error.log warn";

  services.nginx.appendHttpConfig = lib.mkAfter ''
    # Query strings and referers routinely carry live credentials (?token=,
    # ?apikey= for Jellyfin/*arr, presigned-URL signatures, OAuth code/state,
    # password-reset links). Blank the whole value when a sensitive param is
    # present so nothing leaks into ClickHouse; benign queries pass through.
    # It's a blocklist, so the always-safe fields are url/uri, which are
    # path-only by construction (no query string).
    map $args $args_safe {
      default $args;
      "~*(^|&)(password|passwd|pwd|token|api[-_]?key|apikey|secret|access[-_]?token|refresh[-_]?token|auth|sig|signature|x-amz-|code|state|session)=" "redacted";
    }
    map $http_referer $referer_safe {
      default $http_referer;
      "~*[?&](password|passwd|pwd|token|api[-_]?key|apikey|secret|access[-_]?token|refresh[-_]?token|auth|sig|signature|x-amz-|code|state|session)=" "redacted";
    }

    log_format observ_json escape=json '{'
      '"time":"$time_iso8601",'
      '"remote_addr":"$remote_addr",'
      '"host":"$host",'
      '"method":"$request_method",'
      '"uri":"$uri",'
      '"url":"$scheme://$host$uri",'
      '"query":"$args_safe",'
      '"status":$status,'
      '"bytes_sent":$body_bytes_sent,'
      '"request_time":$request_time,'
      '"upstream_addr":"$upstream_addr",'
      '"upstream_status":"$upstream_status",'
      '"upstream_time":"$upstream_response_time",'
      '"content_type":"$sent_http_content_type",'
      '"cache_status":"$upstream_cache_status",'
      '"referer":"$referer_safe",'
      '"user_agent":"$http_user_agent",'
      '"forwarded_for":"$http_x_forwarded_for",'
      '"scheme":"$scheme",'
      '"protocol":"$server_protocol",'
      '"request_id":"$request_id"'
    '}';
    # Also deliberately NOT logged: Authorization, Cookie, Set-Cookie, and
    # API-key request headers. `url`/`uri` are the request PATH only; the raw
    # query lives in the redacted `query` field, never in url.
    access_log /var/log/nginx/access.log observ_json;
  '';

  homelab.observabilityAgent = {
    supplementaryGroups = [ "nginx" ];

    fileLogs.nginx-access = {
      include = [ "/var/log/nginx/access.log" ];
      serviceName = "nginx";
      operators = [
        # JSON line -> typed attributes; a malformed line passes through as
        # body rather than being dropped.
        {
          type = "json_parser";
          parse_from = "body";
          parse_to = "attributes";
          on_error = "send_quiet";
        }
        # HTTP status -> log severity, so 5xx is filterable/alertable as error.
        # The 2xx/3xx/4xx/5xx shorthand is required: the {min,max} range form
        # needs Go int, but the config path delivers float64, so ranges
        # silently no-op and the raw status becomes the severity text.
        {
          type = "severity_parser";
          parse_from = "attributes.status";
          mapping = {
            info = [
              "2xx"
              "3xx"
            ];
            warn = "4xx";
            error = "5xx";
          };
          on_error = "send_quiet";
        }
        # Use nginx's request time as the record timestamp, not ingest time.
        {
          type = "time_parser";
          parse_from = "attributes.time";
          layout_type = "gotime";
          layout = "2006-01-02T15:04:05-07:00";
          on_error = "send_quiet";
        }
      ];
    };

    # Error log stays free text; keep it as a plain receiver.
    fileLogs.nginx-error = {
      include = [ "/var/log/nginx/error.log" ];
      serviceName = "nginx";
    };
  };
}
