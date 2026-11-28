{ config, lib, pkgs, ... }:
# Alerts when a home host stops answering. Every failure alert elsewhere is
# sent by the host that failed, through the house's internet connection, so
# when that goes (as on 2026-11-24, 11 hours until the router was rebooted)
# or a host hangs, nothing is sent at all. wheatley is outside the house and
# runs ntfy itself, so it can still tell you.
#
# Every 2 minutes it pings each host over Tailscale. After `downAfter`
# missed checks it sends one alert; when the host answers again, one more.
let
  hosts = {
    bastion = "100.64.0.4";
    megakill = "100.64.0.10";
  };
  downAfter = 5; # checks, i.e. 10 minutes

  hostWatch = pkgs.writeShellApplication {
    name = "host-watch";
    runtimeInputs = [ pkgs.iputils pkgs.curl pkgs.coreutils ];
    text = ''
      state=$STATE_DIRECTORY
      now=$(date +%s)

      notify() { # title priority tags body
        curl -fsS --retry 3 --max-time 30 \
          -H "Authorization: Bearer $(<"$CREDENTIALS_DIRECTORY/ntfy-token")" \
          -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
          --data-binary "$4" http://127.0.0.1:2586/monitoring >/dev/null
      }

      # A host is marked down only once its alert has gone out, and up again
      # only once that alert has, so an alert ntfy didn't take is retried on
      # the next run.
      undelivered=0
      check() { # name address
        local name=$1 address=$2 misses=0 since
        [ -f "$state/$name.misses" ] && misses=$(<"$state/$name.misses")
        if ping -c 3 -W 2 -q "$address" >/dev/null 2>&1; then
          echo 0 > "$state/$name.misses"
          if [ -f "$state/$name.down" ]; then
            since=$(<"$state/$name.down")
            if notify "$name is reachable again" default white_check_mark \
              "$name answered again after about $(((now - since) / 60)) minutes without contact."; then
              rm -f "$state/$name.down"
            else
              undelivered=1
            fi
          fi
          return
        fi
        misses=$((misses + 1))
        echo "$misses" > "$state/$name.misses"
        echo "$name ($address): no answer, $misses missed"
        if [ "$misses" -ge ${toString downAfter} ] && [ ! -f "$state/$name.down" ]; then
          if notify "$name unreachable from wheatley" high rotating_light \
            "$name ($address) hasn't answered pings over Tailscale for about $((misses * 2)) minutes. The host may be down or hung, or the house's internet connection may be out."; then
            echo $((now - (misses - 1) * 120)) > "$state/$name.down"
          else
            undelivered=1
          fi
        fi
      }

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: address:
        "check ${name} ${address}") hosts)}

      if [ "$undelivered" -eq 1 ]; then
        echo "an alert could not be delivered; retrying next run" >&2
        exit 1
      fi
    '';
  };
in {
  systemd.services.host-watch = {
    description = "Alert when a home host stops answering";
    after = [ "tailscaled.service" "ntfy-sh.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe hostWatch;
      DynamicUser = true;
      AmbientCapabilities = [ "CAP_NET_RAW" ]; # ping
      CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      # Counters survive between runs; a reboot of wheatley just restarts them.
      StateDirectory = "host-watch";
      LoadCredential = "ntfy-token:${config.sops.secrets.ntfy_token.path}";
    };
    # If the check itself breaks, say so (failure-notify.nix).
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
  };
  systemd.timers.host-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2min";
    };
  };
}
