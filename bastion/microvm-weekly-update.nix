{ config, inputs, pkgs, lib, ... }:

let
  # The registry controls which VMs exist. Runtime state controls whether an
  # update may restart a VM; registry autostart remains a boot-time policy.
  vmRegistry = import ./vm-registry.nix;
  vmNames = builtins.attrNames vmRegistry.vms;
  vmLib = import ./lib/vm-lib.nix { inherit lib; };
  microvmPackage =
    inputs.microvm.packages.${pkgs.stdenv.hostPlatform.system}.microvm;

  updateAllMicrovms = pkgs.writeShellApplication {
    name = "microvm-update-all";
    runtimeInputs = [ microvmPackage pkgs.coreutils pkgs.systemd ];
    text = ''
    echo "Starting MicroVM update at $(date)"

    vms=(${lib.concatStringsSep " " vmNames})
    updated=0
    failed=0
    updated_vms=()
    failed_vms=()

    update_vm() {
      local vm="$1"
      local restart=no

      echo ""
      echo "Updating MicroVM: $vm"

      if [[ ! -L "/var/lib/microvms/$vm/current" ]]; then
        echo "Failed: $vm is not installed (run: microvm -c $vm)"
        failed_vms+=("$vm")
        failed=$((failed + 1))
        return
      fi

      # Runtime state is authoritative in both directions: restart an active
      # VM if its runner changes, but never start an inactive VM merely because
      # the registry says to autostart it on the next host boot.
      if systemctl is-active --quiet "microvm@$vm.service"; then
        restart=yes
        echo "Running: updating and restarting only if needed"
      else
        echo "Stopped: updating without starting"
      fi

      if [[ "$restart" == yes ]]; then
        command=(microvm -uR "$vm")
      else
        command=(microvm -u "$vm")
      fi

      if "''${command[@]}" 2>&1; then
        echo "Successfully updated $vm"
        updated_vms+=("$vm")
        updated=$((updated + 1))
      else
        echo "Failed to update $vm"
        failed_vms+=("$vm")
        failed=$((failed + 1))
      fi
    }

    for vm in "''${vms[@]}"; do
      update_vm "$vm"
    done

    echo ""
    echo "========================================="
    echo "MicroVM update completed at $(date)"
    echo "========================================="
    echo "Total: $((updated + failed)) attempted"
    echo "Updated: $updated"
    echo "Failed: $failed"
    echo ""

    if (( updated > 0 )); then
      echo "Successfully updated:"
      printf '  - %s\n' "''${updated_vms[@]}"
      echo ""
    fi
    
    if (( failed > 0 )); then
      echo "Failed to update:"
      printf '  - %s\n' "''${failed_vms[@]}"
      echo ""
      exit 1
    fi
  '';
  };

  # Guests run container-auto-update.service on their own schedule
  # (bastion/modules/container-auto-update.nix) and notify ntfy themselves.
  # This weekly sweep is the safety net for guests that are down, unreachable,
  # or whose timer never fired, none of which a guest can report. The result
  # comes from systemd's job record in the guest journal rather than unit
  # state, which is lost when bastion's weekly update restarts the guest.
  containerUpdateReport = pkgs.writeShellApplication {
    name = "container-auto-update-report";
    runtimeInputs = [ pkgs.openssh pkgs.coreutils pkgs.systemd ];
    text = ''
      vms=(${
        lib.concatStringsSep " "
        (lib.mapAttrsToList (name: vm: "${name}:${vm.ip}") vmLib.getAllVMs)
      })
      checked=0
      failed=0
      report=()

      for entry in "''${vms[@]}"; do
        vm="''${entry%%:*}"
        ip="''${entry#*:}"
        systemctl is-active --quiet "microvm@$vm.service" || continue

        guest() {
          ssh -n -o BatchMode=yes -o ConnectTimeout=10 "admin@$ip" "$@"
        }

        if ! load=$(guest systemctl show container-auto-update.service \
            --property=LoadState --value); then
          report+=("FAIL $vm: unreachable over SSH")
          failed=$((failed + 1))
          checked=$((checked + 1))
          continue
        fi
        [[ "$load" == loaded ]] || continue
        checked=$((checked + 1))

        # Most recent start job for the unit: JOB_RESULT is done or failed.
        job_result="" job_usec=""
        while IFS='=' read -r key value; do
          case "$key" in
            JOB_RESULT) job_result="$value" ;;
            __REALTIME_TIMESTAMP) job_usec="$value" ;;
          esac
        done < <(guest journalctl -q _PID=1 \
          UNIT=container-auto-update.service JOB_TYPE=start \
          -n 1 -o export --output-fields=JOB_RESULT 2>/dev/null || true)

        if [[ -z "$job_result" ]]; then
          report+=("WARN $vm: no recorded run")
          continue
        fi
        when=$(date -d "@$((job_usec / 1000000))" '+%a %F %R %Z')

        if [[ "$job_result" == "done" ]]; then
          report+=("ok   $vm: $when")
        else
          report+=("FAIL $vm: $job_result at $when")
          while IFS= read -r line; do
            report+=("       $line")
          done < <(guest journalctl -u container-auto-update.service \
            --until "@$((job_usec / 1000000 + 1))" \
            -n 5 -o cat --no-pager 2>/dev/null || true)
          failed=$((failed + 1))
        fi
      done

      echo "Total: $checked guests with container auto-update"
      echo "Failed: $failed"
      echo ""
      printf '%s\n' "''${report[@]}"

      (( failed == 0 ))
    '';
  };

in {
  environment.etc."gitconfig".text = ''
    [safe]
      directory = /etc/nixos
  '';

  # Pull latest config from GitHub (picks up Sunday's flake.lock update)
  # Runs as bree to preserve ownership on /home/bree/nixos-configuration
  systemd.services.nixos-config-git-pull = {
    description = "Pull latest nixos-configuration from GitHub";
    serviceConfig = {
      Type = "oneshot";
      User = "bree";
      WorkingDirectory = "/home/bree/nixos-configuration";
      ExecStart = "${pkgs.git}/bin/git pull --ff-only";
      TimeoutStartSec = "120";
      Environment = "GIT_SSH_COMMAND=${pkgs.openssh}/bin/ssh";
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
  };

  systemd.services.microvm-weekly-update = {
    description = "Update all MicroVMs while preserving runtime state";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = lib.getExe updateAllMicrovms;
    };
    unitConfig = {
      ConditionPathExists = "/etc/nixos/bastion/vm-registry.nix";
      OnSuccess = [ "ntfy-unit-result@%n.service" ];
      OnFailure = [ "ntfy-unit-result@%n.service" ];
    };
    # Requires, not Wants: after a failed pull the checkout is stale, so an
    # update would just evaluate outdated config. The pull's own OnFailure
    # notification reports that case.
    after = [ "nixos-config-git-pull.service" ];
    requires = [ "nixos-config-git-pull.service" ];
  };

  systemd.timers.microvm-weekly-update = {
    description = "Timer for weekly MicroVM updates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed *-*-* 03:00:00";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };

  systemd.services.container-auto-update-report = {
    description = "Report MicroVM container auto-update results";
    serviceConfig = {
      Type = "oneshot";
      # bree's key is authorized for admin on every guest.
      User = "bree";
      ExecStart = lib.getExe containerUpdateReport;
    };
    unitConfig = {
      OnSuccess = [ "ntfy-unit-result@%n.service" ];
      OnFailure = [ "ntfy-unit-result@%n.service" ];
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  # After the guests' default container-auto-update window
  # (Wed 10:00-10:15 UTC).
  systemd.timers.container-auto-update-report = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Wed *-*-* 07:30:00";
      Persistent = true;
    };
  };

  # Also expose the same policy-aware updater for manual maintenance.
  environment.systemPackages = [ updateAllMicrovms containerUpdateReport ];
}
