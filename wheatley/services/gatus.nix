{ config, lib, self, ... }:
let
  inherit (lib) attrNames filter;

  # How often every endpoint is checked. With failure-threshold = 3 this means a
  # sustained outage pages after ~3 intervals.
  interval = "20s";

  # Enables the ntfy alert (thresholds come from alerting.ntfy.default-alert).
  ntfyAlert = [{ type = "ntfy"; }];

  # Derive the monitored domains straight from the bastion gateway's live nginx
  # vhosts (bastion/hosts/t0/gateway.nix), so this list can never drift from
  # what's actually being served. We keep only vhosts that reverse-proxy a
  # backend (their "/" location has a proxyPass); this automatically excludes
  # the catch-all default server ("_" -> 404) and apex redirect vhosts
  # (e.g. gaybottoms.org -> chat.gaybottoms.org), which only `return`.
  gatewayVhosts = self.nixosConfigurations.gateway.config.services.nginx.virtualHosts;
  isProxied = name:
    let vh = gatewayVhosts.${name};
    in (vh.locations or { }) ? "/" && (vh.locations."/".proxyPass or null) != null;
  bastionDomains = filter isProxied (attrNames gatewayVhosts);

  # Generic "is the site reachable + TLS healthy" check. We deliberately accept
  # any status < 500 because many of these apps sit behind their own auth and
  # legitimately return 401/403/302. A dead backend surfaces as a 502/503 from
  # the gateway (>= 500) or a failed connection, both of which trip the alert.
  mkBastionEndpoint = host: {
    name = host;
    group = "bastion";
    url = "https://${host}";
    inherit interval;
    conditions = [
      "[CONNECTED] == true"
      "[STATUS] < 500"
      "[CERTIFICATE_EXPIRATION] > 168h"
    ];
    alerts = ntfyAlert;
  };

  # Infrastructure NOT fronted by the bastion gateway (self-hosted on wheatley,
  # plus anything else worth watching). Add hosts here as the fleet grows.
  infraEndpoints = [
    {
      name = "headscale";
      group = "infra";
      url = "https://headscale.whimsical.cloud/health";
      inherit interval;
      conditions = [
        "[CONNECTED] == true"
        "[STATUS] == 200"
        "[CERTIFICATE_EXPIRATION] > 168h"
      ];
      alerts = ntfyAlert;
    }
    {
      # Public path to the push server itself; if this is down, alerts that go
      # out over the internet (phone) would be silently lost.
      name = "ntfy";
      group = "infra";
      url = "https://ntfy.whimsical.cloud/v1/health";
      inherit interval;
      conditions = [
        "[CONNECTED] == true"
        "[STATUS] == 200"
        "[CERTIFICATE_EXPIRATION] > 168h"
      ];
      alerts = ntfyAlert;
    }
  ];

  # Physical hosts pinged directly over Tailscale (Gatus has CAP_NET_RAW for
  # ICMP). Catches a box being down even when it serves no public HTTP. The
  # short MagicDNS name resolves via the resolver's search domain (whimsy.ts).
  mkHostPing = host: {
    name = host;
    group = "hosts";
    url = "icmp://${host}";
    inherit interval;
    conditions = [ "[CONNECTED] == true" ];
    alerts = ntfyAlert;
  };
  hostEndpoints = [
    (mkHostPing "bastion")
  ];
in {
  # ntfy publish token, decrypted from secrets/wheatley.yaml at activation and
  # rendered into a systemd EnvironmentFile (NTFY_TOKEN=...) under /run/secrets.
  sops.secrets."gatus__ntfy_token" = { };
  sops.templates."gatus-env".content = ''
    NTFY_TOKEN=${config.sops.placeholder."gatus__ntfy_token"}
  '';

  services.gatus = {
    enable = true;

    # NTFY_TOKEN is interpolated into the config below; keeps the token out of
    # the world-readable Nix store.
    environmentFile = config.sops.templates."gatus-env".path;

    settings = {
      web = {
        address = "127.0.0.1";
        port = 8085;
      };

      ui = {
        title = "Bree's Homelab Status";
        header = "Bree's Homelab";
      };

      # Persist uptime history to SQLite (default is in-memory, lost on every
      # service restart / rebuild). DB path is persisted via the bind mount below.
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };

      alerting.ntfy = {
        # Publish over localhost so alerts don't depend on nginx/DNS being up.
        url = "http://127.0.0.1:2586";
        topic = "monitoring";
        token = "\${NTFY_TOKEN}";
        priority = 4;
        default-alert = {
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };

      endpoints = infraEndpoints ++ hostEndpoints
        ++ (map mkBastionEndpoint bastionDomains);
    };
  };

  # The upstream module runs Gatus as a DynamicUser, which keeps state under
  # /var/lib/private and would collide with bind-mounting /var/lib/gatus (same
  # issue we hit with ntfy). Define a static user and turn DynamicUser off so
  # the state dir is a plain, bind-mountable directory.
  users.users.gatus = { isSystemUser = true; group = "gatus"; };
  users.groups.gatus = { };
  systemd.services.gatus.serviceConfig.DynamicUser = lib.mkForce false;

  # Persist the sqlite DB on the backed-up /services dataset (root is rolled back
  # to blank on every boot). StateDirectory=gatus fixes ownership at start.
  #   one-time on wheatley:  sudo mkdir -p /services/gatus
  fileSystems."/var/lib/gatus" = {
    device = "/services/gatus";
    fsType = "none";
    options = [ "bind" ];
  };
}
