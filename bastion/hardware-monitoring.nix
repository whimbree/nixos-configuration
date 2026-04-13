{ config, pkgs, ... }: {
  # Hardware monitoring + IPMI access
  environment.systemPackages = with pkgs; [
    lm_sensors
    smartmontools
    ipmitool

    (writeShellScriptBin "fanspeeds" ''
      sudo ${ipmitool}/bin/ipmitool sdr type fan
    '')

    (writeShellScriptBin "fanduties" ''
      # Returns 16 bytes: one duty value (hex, 0-0x64) per fan slot
      echo "Fan duties (slot: duty%)"
      readarray -t bytes < <(sudo ${ipmitool}/bin/ipmitool raw 0x3a 0xda | tr ' ' '\n' | grep -v '^$')
      for i in "''${!bytes[@]}"; do
        slot=$((i + 1))
        pct=$((16#''${bytes[$i]}))
        printf "  FAN%-2d: %3d%%\n" "$slot" "$pct"
      done
    '')

    (writeShellScriptBin "systemp" ''
      sudo ${ipmitool}/bin/ipmitool sdr type temperature
    '')

    (writeShellScriptBin "ipmistatus" ''
      echo "=== Fans ==="
      sudo ${ipmitool}/bin/ipmitool sdr type fan
      echo
      echo "=== Temperatures ==="
      sudo ${ipmitool}/bin/ipmitool sdr type temperature
      echo
      echo "=== Voltages ==="
      sudo ${ipmitool}/bin/ipmitool sdr type voltage
      echo
      echo "=== Power supplies ==="
      sudo ${ipmitool}/bin/ipmitool sdr | grep -iE 'psu|power'
    '')

    (writeShellScriptBin "ipmisel" ''
      # System Event Log - shows hardware errors, BMC events, thermal warnings
      sudo ${ipmitool}/bin/ipmitool sel list | tail -30
    '')

    (writeShellScriptBin "hddtemps" ''
      for d in /dev/sd?; do
        [ "$(cat /sys/block/$(basename $d)/size 2>/dev/null)" = "0" ] && continue
        temp=$(sudo ${smartmontools}/bin/smartctl -A "$d" 2>/dev/null | \
               awk '/Temperature_Celsius|Airflow_Temperature/ {print $10; exit}')
        echo "$d: ''${temp:-N/A}°C"
      done
    '')
  ];

  # Kernel modules:
  #   nct6775       - Nuvoton Super I/O (temps only; fans are BMC-controlled)
  #   ipmi_devintf  - exposes /dev/ipmi0
  #   ipmi_si       - KCS interface to BMC
  boot.kernelModules = [ "nct6775" "ipmi_devintf" "ipmi_si" ];

  # X470D4U doesn't advertise its BMC via ACPI/SMBIOS, so ipmi_si needs
  # the KCS port hardcoded. Port 0xca2 was discovered empirically (sensors-detect
  # reported 0xca0 with low confidence; 0xca2 is what actually works).
  boot.extraModprobeConfig = ''
    options ipmi_si type=kcs ports=0xca2
  '';
}
