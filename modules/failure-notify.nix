{ config, lib, pkgs, ... }:

# Sends a unit's result to ntfy. Units opt in with
#   unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
# (and OnSuccess= for a success report). nixos-upgrade and sanoid are
# hooked up here for every host that imports this module.
#
# Each host has its own publish-only token, stored as ntfy_token in its sops
# file. To create one, on wheatley:
#   ntfy user add <host>
#   ntfy access <host> monitoring write-only
#   ntfy token add <host>        # prints tk_...
# then `sops secrets/<host>.yaml` and set ntfy_token.
let
  host = config.networking.hostName;
  hook = [ "ntfy-unit-result@%n.service" ];

  # systemd withholds the MONITOR_* variables when the same unit is listed in
  # both OnSuccess= and OnFailure= (it sees two trigger candidates), so read
  # the finished unit's Result and InvocationID directly; both persist after
  # it deactivates.
  ntfyUnitResult = pkgs.writeShellApplication {
    name = "ntfy-unit-result";
    runtimeInputs = [ pkgs.curl pkgs.systemd pkgs.coreutils pkgs.gnused ];
    text = ''
      unit="$1"
      result="''${MONITOR_SERVICE_RESULT:-$(systemctl show -P Result "$unit")}"
      invocation="''${MONITOR_INVOCATION_ID:-$(systemctl show -P InvocationID "$unit")}"
      log=$(journalctl "_SYSTEMD_INVOCATION_ID=$invocation" -o cat --no-pager || true)

      # Some jobs print a summary block starting at "Total:"; otherwise
      # fall back to the tail of the run's log.
      if summary=$(sed -n '/^Total:/,$p' <<<"$log") && [[ -n "$summary" ]]; then
        body="$summary"
      else
        body=$(tail -n 15 <<<"$log")
      fi

      if [[ "$result" == success ]]; then
        title="${host}: $unit succeeded"
        priority=default
        tags=white_check_mark
      else
        title="${host}: $unit failed ($result)"
        priority=high
        tags=rotating_light
      fi

      curl -fsS --retry 3 --max-time 30 \
        -H "Authorization: Bearer $(<"$CREDENTIALS_DIRECTORY/ntfy-token")" \
        -H "Title: $title" \
        -H "Priority: $priority" \
        -H "Tags: $tags" \
        --data-binary "''${body:-(no log output)}" \
        https://ntfy.whimsical.cloud/monitoring
    '';
  };
in {
  sops.secrets.ntfy_token = { };

  systemd.services."ntfy-unit-result@" = {
    description = "Send ntfy notification for %i";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe ntfyUnitResult} %i";
      LoadCredential = "ntfy-token:${config.sops.secrets.ntfy_token.path}";
      DynamicUser = true;
      # Reading other units' journal entries needs systemd-journal membership.
      SupplementaryGroups = [ "systemd-journal" ];
    };
  };

  systemd.services.nixos-upgrade.unitConfig.OnFailure =
    lib.mkIf config.system.autoUpgrade.enable hook;
  systemd.services.sanoid.unitConfig.OnFailure =
    lib.mkIf config.services.sanoid.enable hook;
}
