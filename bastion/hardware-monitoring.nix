# hardware-monitoring.nix
#
# Hardware monitoring tools + IPMI setup for ASRock Rack X470D4U.
#
# This module handles the "talk to sensors and BMC" concern. It does NOT
# do fan control — that's in hdd-fan-control.nix, which imports this file
# as its foundation.
#
# What this gives you:
#   - lm_sensors, smartmontools, ipmitool available system-wide
#   - /dev/ipmi0 exposed and working (non-trivial on this board - see below)
#   - A handful of convenience shell scripts for inspecting hardware state
#
# The shell scripts are defined inline via writeShellScriptBin, which
# builds them as proper executables in the Nix store and adds them to
# $PATH. They reference other nixpkgs tools by store path so they don't
# rely on PATH resolution at runtime.

{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    # Core tools.
    lm_sensors # `sensors`, `sensors-detect` - reads hwmon-exposed sensors
    smartmontools # `smartctl` - SMART data from drives (temps, health, etc.)
    ipmitool # talks to the BMC via /dev/ipmi0

    # `fanspeeds` - show current RPM of every fan header.
    # Useful at-a-glance check. Shows "No Reading" for unpopulated headers.
    (writeShellScriptBin "fanspeeds" ''
      sudo ${ipmitool}/bin/ipmitool sdr type fan
    '')

    # `fanduties` - show the current PWM duty cycle per fan slot as a %.
    # Different from fanspeeds (RPM) - this is what the BMC is *telling* the
    # fan to do, not what it's actually doing. Useful for confirming that the
    # fan-control daemon is setting the duty you expect.
    #
    # The BMC's raw response to 0x3a 0xda is 16 hex bytes. We parse them
    # into decimal percentages. Slots 7-16 are padding on this board and
    # typically read 0x00.
    (writeShellScriptBin "fanduties" ''
      echo "Fan duties (slot: duty%)"
      readarray -t bytes < <(sudo ${ipmitool}/bin/ipmitool raw 0x3a 0xda | tr ' ' '\n' | grep -v '^$')
      for i in "''${!bytes[@]}"; do
        slot=$((i + 1))
        # 16#XX is bash syntax for "interpret XX as base-16".
        # The ''${bytes[$i]} below uses Nix's escape for a literal dollar-brace
        # inside an indented string, so bash (not Nix) gets to expand it.
        pct=$((16#''${bytes[$i]}))
        printf "  FAN%-2d: %3d%%\n" "$slot" "$pct"
      done
    '')

    # `systemp` - BMC-reported temperatures (CPU, motherboard, DIMMs, etc).
    # Complements `hddtemps` and `sensors` - this is what the management
    # controller itself sees, which can occasionally differ from what the OS
    # sees via the Nuvoton chip.
    (writeShellScriptBin "systemp" ''
      sudo ${ipmitool}/bin/ipmitool sdr type temperature
    '')

    # `ipmistatus` - everything-at-a-glance dashboard.
    # Handy when something feels wrong and you want a quick overview
    # without running four separate commands.
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

    # `ipmisel` - System Event Log (last 30 entries).
    # This is the BMC's persistent log of notable hardware events: thermal
    # excursions, ECC errors, chassis intrusion, power supply faults, etc.
    # First place to check when something mysterious happens ("why did my
    # fans spike at 3am?"). Events have timestamps and persist across reboots.
    # Clear it with `sudo ipmitool sel clear` once you've investigated.
    (writeShellScriptBin "ipmisel" ''
      sudo ${ipmitool}/bin/ipmitool sel list | tail -30
    '')

    # `hddtemps` - print temperature of every populated /dev/sd? drive.
    # Filters out drives with zero size (empty hot-swap slots, card readers).
    # Works for both ATA (column-format Temperature_Celsius attribute) and
    # most SATA drives. SAS drives use a different attribute format not
    # handled here - see smartctl -a for those.
    (writeShellScriptBin "hddtemps" ''
      for d in /dev/sd?; do
        [ "$(cat /sys/block/$(basename $d)/size 2>/dev/null)" = "0" ] && continue
        temp=$(sudo ${smartmontools}/bin/smartctl -A "$d" 2>/dev/null | \
               awk '/Temperature_Celsius|Airflow_Temperature/ {print $10; exit}')
        echo "$d: ''${temp:-N/A}°C"
      done
    '')
  ];

  # Kernel modules we need loaded at boot:
  #
  #   nct6775       Nuvoton Super I/O driver. On this board it exposes CPU
  #                 and system temperatures, voltages, etc. It CANNOT control
  #                 the fans - those are BMC-managed - but the temp readings
  #                 are still useful (complements `systemp` from the BMC).
  #
  #   ipmi_devintf  Creates /dev/ipmi0 character device for userspace tools
  #                 (like ipmitool) to talk to the BMC.
  #
  #   ipmi_si       The IPMI System Interface driver. Probes for the BMC via
  #                 various transport mechanisms (KCS, SMIC, BT, SSIF). On
  #                 this board we have to tell it exactly where to look -
  #                 see below.
  boot.kernelModules = [ "nct6775" "ipmi_devintf" "ipmi_si" ];

  # The X470D4U's BMC doesn't advertise itself via ACPI DSDT or SMBIOS
  # Type 38 entries, which are the standard mechanisms ipmi_si uses for
  # auto-detection. Without hardcoded parameters, ipmi_si loads, finds
  # nothing, and silently gives up with "Unable to find any System
  # Interface(s)" in dmesg.
  #
  # The fix: tell the driver explicitly that there's a KCS interface at
  # I/O port 0xca2. This was discovered empirically:
  #
  #   - `sensors-detect` reports a BMC KCS at 0xca0 with "confidence 4"
  #   - But `ipmi_si type=kcs ports=0xca0` fails with "Interface
  #     detection failed"
  #   - `ipmi_si type=kcs ports=0xca2` succeeds and initializes cleanly
  #
  # My best guess: KCS has command and data registers at consecutive
  # addresses. `sensors-detect` may be detecting *something* at 0xca0
  # (the data register?) while the command register the driver needs
  # lives at 0xca2. But this is speculation - the board just works with
  # 0xca2, and that's what matters.
  boot.extraModprobeConfig = ''
    options ipmi_si type=kcs ports=0xca2
  '';
}
