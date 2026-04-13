{ config, pkgs, ... }: {
  # Hardware monitoring + IPMI access
  environment.systemPackages = with pkgs; [
    lm_sensors
    smartmontools
    ipmitool

    (writeShellScriptBin "hddtemps" ''
      for d in /dev/sd?; do
        [ "$(cat /sys/block/$(basename $d)/size 2>/dev/null)" = "0" ] && continue
        temp=$(${smartmontools}/bin/smartctl -A "$d" 2>/dev/null | \
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
