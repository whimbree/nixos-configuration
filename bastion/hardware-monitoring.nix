{ config, pkgs, ... }:
{
  # Hardware monitoring + IPMI access
  environment.systemPackages = with pkgs; [
    lm_sensors
    smartmontools
    ipmitool
  ];

  # Kernel modules:
  # - nct6775: Nuvoton Super I/O sensors (temps, though fans are BMC-controlled)
  # - ipmi_devintf + ipmi_si: expose BMC as /dev/ipmi0
  boot.kernelModules = [
    "nct6775"
    "ipmi_devintf"
    "ipmi_si"
  ];

  # The ASRock Rack X470D4U doesn't advertise its BMC via ACPI/SMBIOS,
  # so ipmi_si needs the KCS port hardcoded.
  boot.extraModprobeConfig = ''
    options ipmi_si type=kcs ports=0xca2
  '';
}
