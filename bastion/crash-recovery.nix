{ ... }:
# Reboot instead of staying hung or half-working, and keep evidence of why.
#
# A reboot still stops at the cryptkey prompt (SSH unlock in the initrd), so
# this turns a hang into "waiting for the passphrase", not into a recovery on
# its own. wheatley's host-watch alerts when bastion stops answering.
{
  # The chipset's SP5100 TCO watchdog: systemd pets it, and if the kernel or
  # PID 1 stops for a minute, the hardware resets the machine.
  # RebootWatchdogSec (default 10min) covers a shutdown that hangs.
  systemd.settings.Manager.RuntimeWatchdogSec = "60s";

  # After a panic, reboot in 30 seconds instead of sitting there; and treat
  # an oops as a panic, since a kernel that oopsed (in ZFS, KVM, a driver)
  # can't be trusted to keep the VMs' data safe.
  boot.kernelParams = [ "panic=30" ];
  boot.kernel.sysctl."kernel.panic_on_oops" = 1;

  # Panic and oops logs the kernel saved in EFI variables (efi_pstore) are
  # moved into the journal on the next boot, which survives reboots
  # (rpool/local/log), and deleted from the EFI variables. Look with
  #   journalctl -b -1 -u systemd-pstore    # or -k on the boot that crashed
  environment.etc."systemd/pstore.conf".text = ''
    [PStore]
    Storage=journal
    Unlink=yes
  '';
}
