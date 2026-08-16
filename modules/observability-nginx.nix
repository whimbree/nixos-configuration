# Structured nginx access logging for observability producers.
#
# nginx writes access logs as one JSON object per request; the agent's filelog
# receiver parses that into typed attributes (status, host, method, uri,
# request_time, upstream, request_id, ...) so HyperDX/ClickHouse can facet and
# aggregate on them instead of substring-matching a text line. Import on any
# nginx host that also runs the observability agent.
{ lib, ... }:
{
  services.nginx.logError = lib.mkDefault "/var/log/nginx/error.log warn";

  services.nginx.appendHttpConfig = lib.mkAfter ''
    log_format observ_json escape=json '{'
      '"time":"$time_iso8601",'
      '"remote_addr":"$remote_addr",'
      '"host":"$host",'
      '"method":"$request_method",'
      '"uri":"$uri",'
      '"query":"$args",'
      '"status":$status,'
      '"bytes_sent":$body_bytes_sent,'
      '"request_time":$request_time,'
      '"upstream_addr":"$upstream_addr",'
      '"upstream_status":"$upstream_status",'
      '"upstream_time":"$upstream_response_time",'
      '"content_type":"$sent_http_content_type",'
      '"cache_status":"$upstream_cache_status",'
      '"referer":"$http_referer",'
      '"user_agent":"$http_user_agent",'
      '"forwarded_for":"$http_x_forwarded_for",'
      '"scheme":"$scheme",'
      '"protocol":"$server_protocol",'
      '"request_id":"$request_id"'
    '}';
    # Deliberately NOT logged: Authorization, Cookie, Set-Cookie, and API-key
    # headers. They carry live credentials/session tokens, and logging them
    # would copy secrets into ClickHouse where any HyperDX viewer could read
    # them. Curated non-sensitive fields only.
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
        {
          type = "severity_parser";
          parse_from = "attributes.status";
          mapping = {
            info = [ { min = 200; max = 399; } ];
            warn = [ { min = 400; max = 499; } ];
            error = [ { min = 500; max = 599; } ];
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
