# hdd-fan-control.nix
#
# HDD fan control for ASRock Rack X470D4U (AST2500 BMC, firmware 3.02+)
#
# =============================================================================
# BACKGROUND
# =============================================================================
# The X470D4U routes all fan headers through the AST2500 BMC, not through the
# Nuvoton NCT6779 Super I/O chip. That means:
#   - `sensors` shows fan1..fan5 at 0 RPM (nct6775 can't read them)
#   - `pwmconfig` / `fancontrol` from lm_sensors cannot control these fans
#   - All fan monitoring and control happens via IPMI to the BMC
#
# The BMC firmware went through a regression cycle:
#   - Old firmware: `ipmitool raw 0x3a 0x01 <6 bytes>` worked
#   - BMC 2.x:      that command was broken
#   - BMC 3.02:     new AST2500 command family replaced it
#
# =============================================================================
# COMMAND REFERENCE (AST2500, BMC 3.02+)
# =============================================================================
#
#   Set fan modes (16 bytes, one per slot):
#     ipmitool raw 0x3a 0xd8 <m1> <m2> ... <m16>
#     where each <mN> is:
#       0x0 = BMC automatic (smart fan curve from BIOS/IPMI settings)
#       0x1 = manual (duty set by 0xd6)
#
#   Set fan duties (16 bytes, one per slot, 0x00..0x64 = 0-100%):
#     ipmitool raw 0x3a 0xd6 <d1> <d2> ... <d16>
#     IMPORTANT QUIRKS we discovered empirically:
#       - MUST be exactly 16 bytes (rsp 0xc7 "length invalid" otherwise)
#       - Duty values below ~0x14 (20%) are REJECTED (rsp 0xcc "invalid
#         data field") even in slots whose fans are set to auto mode
#       - Workaround: fill ALL slots with a "safe" value (we use 0x64).
#         Values in auto-mode slots are IGNORED by the BMC, so this does
#         NOT override the auto curve for those fans. Only manual-mode
#         slots actually consume their duty byte.
#
#   Read current fan duties:
#     ipmitool raw 0x3a 0xda
#     Returns 16 bytes. When all fans are on auto, returns 0x1e (30%) for
#     populated slots and 0x00 for unpopulated ones.
#
#   Read current fan modes (firmware-dependent):
#     ipmitool raw 0x3a 0xd7
#     On BMC 3.02 this returns rsp 0xcc; not essential for operation.
#
# =============================================================================
# SLOT MAPPING ON THIS BOARD
# =============================================================================
#   Slot 1 (byte 1)  -> FAN1  = CPU fan       [leave on BMC auto]
#   Slot 2 (byte 2)  -> FAN2  = top case fan  [leave on BMC auto]
#   Slot 3 (byte 3)  -> FAN3  = empty
#   Slot 4 (byte 4)  -> FAN4  = empty
#   Slot 5 (byte 5)  -> FAN5  = HDD cage fan  [CONTROL THIS]
#   Slot 6 (byte 6)  -> FAN6  = HDD cage fan  [CONTROL THIS]
#   Slots 7-16       -> padding (no physical header)
#
# =============================================================================
# OTHER BMC BEHAVIOR NOTES
# =============================================================================
#   - Manual mode and duty values do NOT persist across BMC reboots or AC
#     power cycles. The daemon re-asserts manual mode every poll cycle so
#     fan control recovers automatically from transient BMC restarts.
#   - The BMC may override manual duty settings if critical thermal
#     thresholds are crossed (thermal protection). This is intended.
#   - ipmitool occasionally reports "Received a response with unexpected ID";
#     these are transient and the daemon retries automatically.
#
# =============================================================================

{ config, pkgs, lib, ... }:

let
  # Which slots (1-indexed) are the HDD cage fans
  hddFanSlots = [ 5 6 ];

  # Temperature -> duty cycle curve.
  # Below minTempC: duty = minDutyPct (floor - fans never drop below this)
  # Above maxTempC: duty = 100%
  # Between: linear interpolation
  minTempC = 32;
  maxTempC = 60;
  minDutyPct = 35;   # 35% floor - quiet at idle, plenty of ramp headroom
  maxDutyPct = 100;

  fanControlScript = pkgs.writers.writePython3 "hdd-fan-control" {
    flakeIgnore = [ "E501" ];  # allow long lines in docstrings/logs
  } ''
    """
    HDD fan controller for ASRock Rack X470D4U (AST2500 BMC).

    Polls SMART temperatures from all /dev/sd? drives with non-zero size,
    takes the max, maps it to a fan duty cycle via a linear ramp with a
    minimum floor, and sets the HDD cage fans via IPMI. CPU and case fans
    are left on BMC auto control.

    See the enclosing Nix module for protocol details and command reference.
    """
    import glob
    import os
    import subprocess
    import sys
    import time

    # --- Configuration (injected from Nix) ---
    HDD_FAN_SLOTS = [${lib.concatStringsSep ", " (map toString hddFanSlots)}]
    MIN_TEMP_C = ${toString minTempC}
    MAX_TEMP_C = ${toString maxTempC}
    MIN_DUTY_PCT = ${toString minDutyPct}
    MAX_DUTY_PCT = ${toString maxDutyPct}
    POLL_INTERVAL_S = 60

    # --- BMC protocol constants ---
    NUM_SLOTS = 16  # BMC command expects exactly 16 bytes regardless of board
    # BMC rejects duty bytes below ~0x14 (20%). Clamp to this floor even though
    # MIN_DUTY_PCT should already be well above it.
    BMC_MIN_DUTY = 0x14
    # The BMC rejects low duty bytes even for auto-mode slots.
    # We fill auto-mode slots with this value; the BMC ignores it for those fans.
    FILLER_DUTY = 0x64

    IPMITOOL = "${pkgs.ipmitool}/bin/ipmitool"
    SMARTCTL = "${pkgs.smartmontools}/bin/smartctl"


    def list_drives():
        """Return list of /dev/sd? paths with non-zero size (skips empty slots)."""
        drives = []
        for path in sorted(glob.glob('/dev/sd?')):
            name = os.path.basename(path)
            try:
                with open(f'/sys/block/{name}/size') as f:
                    if f.read().strip() != '0':
                        drives.append(path)
            except FileNotFoundError:
                continue
        return drives


    def drive_temp(path):
        """Return temperature in Celsius for a drive, or None if unreadable."""
        try:
            out = subprocess.check_output(
                [SMARTCTL, '-A', path],
                stderr=subprocess.DEVNULL,
                timeout=15,
            ).decode('utf-8', errors='ignore')
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return None
        for line in out.splitlines():
            # ATA attribute table format: raw value is column 10 (0-indexed: 9)
            if 'Temperature_Celsius' in line or 'Airflow_Temperature' in line:
                parts = line.split()
                try:
                    return int(parts[9])
                except (ValueError, IndexError):
                    continue
            # SAS format: single-line "Current Drive Temperature: NN C"
            if 'Current Drive Temperature' in line:
                try:
                    return int(line.split(':')[1].strip().split()[0])
                except (ValueError, IndexError):
                    continue
        return None


    def temp_to_duty(temp_c):
        """Linear ramp from MIN_TEMP_C->MIN_DUTY_PCT to MAX_TEMP_C->MAX_DUTY_PCT."""
        if temp_c <= MIN_TEMP_C:
            return MIN_DUTY_PCT
        if temp_c >= MAX_TEMP_C:
            return MAX_DUTY_PCT
        span_t = MAX_TEMP_C - MIN_TEMP_C
        span_d = MAX_DUTY_PCT - MIN_DUTY_PCT
        return int(MIN_DUTY_PCT + ((temp_c - MIN_TEMP_C) / span_t) * span_d)


    def log(msg):
        print(msg, flush=True)


    def ipmi_call(args, retries=3):
        """Run ipmitool with retry on transient 'unexpected ID' errors."""
        last_exc = None
        for attempt in range(retries):
            try:
                subprocess.check_call(
                    [IPMITOOL] + args,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                return
            except subprocess.CalledProcessError as e:
                last_exc = e
                log(f"ipmitool failed (attempt {attempt + 1}/{retries}): {e}")
                time.sleep(1)
        raise last_exc


    def set_modes(manual_slots):
        """Set fan modes: slots in manual_slots go manual (0x1), others auto (0x0)."""
        modes = [0x0] * NUM_SLOTS
        for slot in manual_slots:
            modes[slot - 1] = 0x1
        ipmi_call(['raw', '0x3a', '0xd8'] + [hex(m) for m in modes])


    def set_duty(duty_pct, manual_slots):
        """Set duty on manual_slots; fill rest with FILLER_DUTY (ignored by BMC)."""
        duty_byte = max(BMC_MIN_DUTY, min(0x64, duty_pct))
        duties = [FILLER_DUTY] * NUM_SLOTS
        for slot in manual_slots:
            duties[slot - 1] = duty_byte
        ipmi_call(['raw', '0x3a', '0xd6'] + [hex(d) for d in duties])


    def main():
        log(f"hdd-fan-control starting: slots={HDD_FAN_SLOTS} "
            f"temp={MIN_TEMP_C}-{MAX_TEMP_C}C duty={MIN_DUTY_PCT}-{MAX_DUTY_PCT}%")
        last_duty = None
        try:
            while True:
                # Re-assert manual mode every cycle. BMC resets (watchdog, power
                # glitch) silently revert fans to auto, and re-setting is cheap.
                set_modes(HDD_FAN_SLOTS)

                temps = {}
                for d in list_drives():
                    t = drive_temp(d)
                    if t is not None:
                        temps[d] = t
                if not temps:
                    log("WARNING: no drive temps readable, forcing 100%")
                    duty = MAX_DUTY_PCT
                    max_temp = None
                else:
                    max_temp = max(temps.values())
                    duty = temp_to_duty(max_temp)
                if duty != last_duty:
                    set_duty(duty, HDD_FAN_SLOTS)
                    temp_str = (f"max_temp={max_temp}C"
                                if max_temp is not None else "max_temp=?")
                    log(f"{temp_str} duty={duty}% drives={len(temps)}")
                    last_duty = duty
                time.sleep(POLL_INTERVAL_S)
        except KeyboardInterrupt:
            pass
        finally:
            log("shutting down, returning fans to BMC auto control")
            try:
                set_modes([])
            except Exception as e:
                log(f"failed to restore auto mode: {e}")
                sys.exit(1)


    if __name__ == '__main__':
        main()
  '';
in
{
  imports = [ ./hardware-monitoring.nix ];

  systemd.services.hdd-fan-control = {
    description = "HDD fan control via IPMI (ASRock Rack X470D4U)";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = fanControlScript;
      Restart = "on-failure";
      RestartSec = 30;
      # Needs root: ipmitool talks to /dev/ipmi0, smartctl needs raw device access
    };
  };
}
