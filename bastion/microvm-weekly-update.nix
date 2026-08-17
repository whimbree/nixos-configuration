{ inputs, pkgs, lib, ... }:

let
  # The registry controls which VMs exist. Runtime state controls whether an
  # update may restart a VM; registry autostart remains a boot-time policy.
  vmRegistry = import ./vm-registry.nix;
  vmNames = builtins.attrNames vmRegistry.vms;
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
    };
    after = [ "nixos-config-git-pull.service" ];
    wants = [ "nixos-config-git-pull.service" ];
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

  # Also expose the same policy-aware updater for manual maintenance.
  environment.systemPackages = [ updateAllMicrovms ];
}
