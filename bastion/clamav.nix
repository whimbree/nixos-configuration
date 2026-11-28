{ config, pkgs, lib, ... }:
let
  # Scheduled scans of /ocean/media, for anything the downloaders left there
  # (an .exe in a torrent, say), through the running clamd so the signatures
  # aren't loaded twice:
  # - weekly: every file new or changed since the last clean weekly scan, at
  #   any size, plus every file under 100M (new signatures, old files)
  # - monthly: everything (clamd skips files over its MaxFileSize)
  # A detection (exit 1) or error (exit 2) fails the unit, which alerts.
  # Infected files go to the quarantine.
  #
  # `before` sets the find filter; `after` runs only after a clean scan
  # (the script stops at the scan's non-zero exit).
  scanService = { description, before, after ? "" }: {
    inherit description;
    after = [ "clamav-daemon.service" ];
    requires = [ "clamav-daemon.service" ];
    path = [ pkgs.clamav pkgs.findutils pkgs.coreutils ];
    unitConfig.OnFailure = [ "ntfy-unit-result@%n.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Excluded from on-access scanning (OnAccessExcludeUname), so files
      # aren't scanned twice. Reads every file and moves infected ones to the
      # quarantine through these capabilities rather than as root.
      User = "clamav-scan";
      Group = "clamav-scan";
      AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" "CAP_DAC_OVERRIDE" ];
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" "CAP_DAC_OVERRIDE" ];
    };
    script = ''
      ${before}
      find /ocean/media -type f "''${filter[@]}" -print |
        clamdscan --multiscan --fdpass --infected \
          --move=/persist/var/clamav-quarantine --file-list=-
      ${after}
    '';
  };

  # In /persist: /var is wiped on boot.
  stateDir = "/persist/var/lib/clamav-media-scan";
in {
  environment.systemPackages = with pkgs; [ killall ];

  # enable antivirus clamav and
  # update the signatures' database every hour
  services.clamav = {
    daemon.enable = true;
    daemon.settings = {
      OnAccessIncludePath = [
        "/ocean/downloads"
        "/ocean/nas"
        "/ocean/public"
        "/ocean/services"
        "/ocean/media"
        "/neptune/media"
      ];
      OnAccessPrevention = "yes";
      # clamav-scan: the scheduled scans below. mkForce: the clamav module
      # sets "clamav" itself.
      OnAccessExcludeUname = lib.mkForce [ "clamav" "clamav-scan" ];
      OnAccessMaxThreads = "10";
      OnAccessExtraScanning = "yes";
      MaxThreads = "100";
      MaxQueue = "100";
      LogFile = "/var/log/clamav/clamd.log";
      LogTime = "yes";
      LogFileMaxSize = "2M";
      ExtendedDetectionInfo = "yes";
      MaxScanSize = "4000M";
      MaxFileSize = "4000M";
      MaxScanTime = "60000";
      StreamMaxLength = "4000M";
      BytecodeTimeout = "60000";
    };
    updater.enable = true;
    updater.frequency = 24;
  };

  systemd.services.clamonacc = {
    enable = true;
    description = "ClamAV On-Access Scanner";
    path = [ pkgs.clamav pkgs.killall ];
    serviceConfig = {
      Type = "simple";
      ExecStart =
        "${pkgs.clamav}/bin/clamonacc --move=/persist/var/clamav-quarantine --log=/var/log/clamav/clamonacc.log --wait --foreground";
      ExecStop = "${pkgs.killall}/bin/killall -9 clamonacc";
      Restart = "on-failure";
    };
    requires = [ "clamav-daemon.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  users.users.clamav-scan = {
    isSystemUser = true;
    group = "clamav-scan";
  };
  users.groups.clamav-scan = { };
  systemd.tmpfiles.rules = [ "d ${stateDir} 0700 clamav-scan clamav-scan -" ];

  systemd.services.clamav-media-scan = scanService {
    description = "Weekly ClamAV scan of new and small files in /ocean/media";
    # Change time, so files moved in from /ocean/downloads count as new.
    before = ''
      stamp=${stateDir}/last-clean-scan
      touch "$stamp.next"
      if [ -e "$stamp" ]; then since=(-cnewer "$stamp"); else since=(-ctime -8); fi
      filter=( \( -size -100M -o "''${since[@]}" \) )
    '';
    after = ''
      mv "$stamp.next" "$stamp"
    '';
  };

  systemd.services.clamav-media-scan-full = scanService {
    description = "Monthly ClamAV scan of all of /ocean/media";
    before = "filter=()";
  };

  systemd.timers = {
    clamav-media-scan = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sat *-*-* 00:00:00";
        Persistent = true;
      };
    };
    # First Sunday of the month, so it doesn't overlap the weekly scan.
    clamav-media-scan-full = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-01..07 00:00:00";
        Persistent = true;
      };
    };
  };
}
