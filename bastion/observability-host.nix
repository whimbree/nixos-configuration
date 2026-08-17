{
  config,
  lib,
  pkgs,
  observability,
  ...
}:
let
  inherit (observability.storage) clickhouseDevice clickhouseZvol;
  vmName = observability.vm.hostname;
in
{
  # microvm@.service runs as the unprivileged microvm:kvm identity. Grant that
  # group access only to the operator-created ClickHouse zvol, not to the broad
  # disk group or other host block devices.
  services.udev.extraRules = lib.optionalString config.boot.zfs.enabled ''
    ACTION=="add|change", KERNEL=="zd*", SUBSYSTEM=="block", PROGRAM=="${config.boot.zfs.package}/lib/udev/zvol_id $devnode", RESULT=="${clickhouseZvol}", OWNER="root", GROUP="kvm", MODE="0660"
  '';

  systemd.services.observability-zvol-permissions = {
    description = "Apply and verify observability zvol device permissions";
    after = [
      "systemd-udevd.service"
      "zfs-import.target"
    ];
    before = [ "microvm@${vmName}.service" ];
    path = [
      pkgs.coreutils
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      if [[ ! -b ${lib.escapeShellArg clickhouseDevice} ]]; then
        echo "Required observability zvol is absent: ${clickhouseDevice}" >&2
        exit 1
      fi

      udevadm trigger \
        --action=change \
        --name-match=${lib.escapeShellArg clickhouseDevice} \
        --settle

      permissions=$(stat -Lc '%G:%a' ${lib.escapeShellArg clickhouseDevice})
      if [[ "$permissions" != "kvm:660" ]]; then
        echo "Unexpected observability zvol permissions: $permissions" >&2
        exit 1
      fi
    '';
  };

  systemd.services."microvm@${vmName}" = {
    # This is an instance-specific extension of the generic imperative
    # microvm@.service, not a replacement unit. Without a drop-in, the
    # generated instance file shadows the template and has no ExecStart.
    overrideStrategy = "asDropin";
    after = [ "observability-zvol-permissions.service" ];
    requires = [ "observability-zvol-permissions.service" ];
  };
}
