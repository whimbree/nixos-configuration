{ inputs, pkgs, lib, ... }:

let
  # Import your VM registry
  vmRegistry = import ./vm-registry.nix;

  # Extract just the VM names
  vmNames = builtins.attrNames vmRegistry.vms;

  # Create the update script
  updateScript = pkgs.writeShellScript "update-all-microvms" ''
    set -e

    echo "Starting MicroVM weekly update at $(date)"

    vms=(${lib.concatStringsSep " " vmNames})
    updated=0
    failed=0
    updated_vms=()
    failed_vms=()
    skipped_vms=()

    for vm in "''${vms[@]}"; do
      echo "Updating MicroVM: $vm"
      if systemctl is-active --quiet "microvm@$vm.service"; then
        echo "Running microvm -uR for $vm"
        if ${inputs.microvm.packages.${pkgs.stdenv.hostPlatform.system}.microvm}/bin/microvm -uR "$vm" 2>&1; then
          echo "Successfully updated $vm"
          updated_vms+=("$vm")
          : $((updated++))
        else
          echo "Failed to update $vm"
          failed_vms+=("$vm")
          : $((failed++))
        fi
      else
        echo "$vm is not running, skipping"
        skipped_vms+=("$vm")
      fi
    done

    echo ""
    echo "========================================="
    echo "MicroVM update completed at $(date)"
    echo "========================================="
    echo "Total: $((updated + failed)) attempted"
    echo "Updated: $updated"
    echo "Failed: $failed"
    echo "Skipped: ''${#skipped_vms[@]}"
    echo ""

    if [ $updated -gt 0 ]; then
      echo "Successfully updated:"
      printf '  - %s\n' "''${updated_vms[@]}"
      echo ""
    fi
    
    if [ $failed -gt 0 ]; then
      echo "Failed to update:"
      printf '  - %s\n' "''${failed_vms[@]}"
      echo ""
    fi
    
    if [ ''${#skipped_vms[@]} -gt 0 ]; then
      echo "Skipped (not running):"
      printf '  - %s\n' "''${skipped_vms[@]}"
      echo ""
    fi
    
    exit 0
  '';

in {
  environment.etc."gitconfig".text = ''
    [safe]
      directory = /etc/nixos
  '';

  # Service that does the actual update
  systemd.services.microvm-weekly-update = {
    description = "Update all MicroVMs with microvm -uR";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${updateScript}";
    };
    # Only run if we have MicroVMs
    unitConfig = {
      ConditionPathExists = "/etc/nixos/bastion/vm-registry.nix";
    };
  };

  systemd.timers.microvm-weekly-update = {
    description = "Timer for weekly MicroVM updates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # Every Wednesday at 3:00 AM
      OnCalendar = "Wed *-*-* 03:00:00";
      # If the system was off at 3am, run at next boot (within 1 hour)
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };
}
