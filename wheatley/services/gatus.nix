{ config, lib, self, ... }:
let
  inherit (lib) attrNames filter;

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
    interval = "60s";
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
      interval = "60s";
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
      interval = "60s";
      conditions = [
        "[CONNECTED] == true"
        "[STATUS] == 200"
        "[CERTIFICATE_EXPIRATION] > 168h"
      ];
      alerts = ntfyAlert;
    }

    # Example: ping a host directly over Tailscale (uncomment + adjust). Gatus
    # has CAP_NET_RAW for ICMP. Useful for boxes that serve no public HTTP.
    # {
    #   name = "bastion";
    #   group = "hosts";
    #   url = "icmp://bastion";
    #   interval = "60s";
    #   conditions = [ "[CONNECTED] == true" ];
    #   alerts = ntfyAlert;
    # }
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
        title = "whimsical.cloud status";
        header = "whimsical.cloud";
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

      endpoints = infraEndpoints ++ (map mkBastionEndpoint bastionDomains);
    };
  };
}
