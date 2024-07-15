{ config, pkgs, lib, ... }: {
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
      OnAccessExcludePath = "/ocean/services/monerod";
      OnAccessPrevention = "yes";
      OnAccessExcludeUname = "clamav";
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

  environment.etc."scripts/clamav-autoscan".source =
    "/persist/etc/scripts/clamav-autoscan";

  services.cron = {
    enable = true;
    systemCronJobs = [ "0 0 * * SAT root /etc/scripts/clamav-autoscan" ];
  };
}
