{ config, pkgs, lib, ... }: {
  # Note: when adding user do not forget to run `smbpasswd -a <USER>`.
  services.samba = {
    enable = true;
    openFirewall = true;
    securityType = "user";
    extraConfig = ''
      workgroup = WORKGROUP
      server role = standalone server
      dns proxy = no
      vfs objects = catia streams_xattr
      pam password change = yes
      map to guest = bad user
      usershare allow guests = yes
      create mask = 0664
      force create mode = 0664
      directory mask = 0775
      force directory mode = 0775
      follow symlinks = yes
      load printers = no
      printing = bsd
      printcap name = /dev/null
      disable spoolss = yes
      strict locking = no
      aio read size = 0
      aio write size = 0
      vfs objects = acl_xattr catia streams_xattr
      inherit permissions = yes
      # Security
      client ipc max protocol = SMB3
      client ipc min protocol = SMB2_10
      client max protocol = SMB3
      client min protocol = SMB2_10
      server max protocol = SMB3
      server min protocol = SMB2_10
    '';
    shares = {
      public = {
        path = "/ocean/public";
        browseable = "yes";
        # This is public, everybody can access.
        "read only" = "yes";
        "guest ok" = "yes";
        "force user" = "fileshare";
        "force group" = "fileshare";

        # These users have r/w access
        "write list" = "fileshare";

        "veto files" =
          "/.apdisk/.DS_Store/.TemporaryItems/.Trashes/desktop.ini/ehthumbs.db/Network Trash Folder/Temporary Items/Thumbs.db/";
        "delete veto files" = "yes";
      };
      downloads = {
        path = "/ocean/downloads";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "no";
        "force user" = "fileshare";
        "force group" = "fileshare";

        # These users have r/w access
        "write list" = "fileshare";

        "veto files" =
          "/.apdisk/.DS_Store/.TemporaryItems/.Trashes/desktop.ini/ehthumbs.db/Network Trash Folder/Temporary Items/Thumbs.db/";
        "delete veto files" = "yes";
      };
      media = {
        path = "/ocean/media";
        browseable = "yes";
        "read only" = "yes";
        "guest ok" = "no";
        "force user" = "fileshare";
        "force group" = "fileshare";

        # These users have r/w access
        "write list" = "fileshare";

        "veto files" =
          "/.apdisk/.DS_Store/.TemporaryItems/.Trashes/desktop.ini/ehthumbs.db/Network Trash Folder/Temporary Items/Thumbs.db/";
        "delete veto files" = "yes";
      };
    };
  };

  # create fileshare user for public samba shares
  users.users.fileshare = {
    createHome = false;
    isSystemUser = true;
    group = "fileshare";
    uid = 1420;
  };
  users.groups.fileshare.gid = 1420;

  # mDNS
  services.avahi = {
    enable = true;
    openFirewall = true;
    nssmdns = true;
    allowInterfaces = [ "enp36s0" ];
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
    extraServiceFiles = {
      smb = ''
        <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
        </service-group>
      '';
    };
  };

  systemd.services.docker-modprobe-nfs = {
    enable = true;
    description = "modprobe nfs";
    path = [ pkgs.kmod ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.kmod}/bin/modprobe nfs";
      ExecStop = "${pkgs.kmod}/bin/modprobe -r nfs";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.docker-modprobe-nfsd = {
    enable = true;
    description = "modprobe nfsd";
    path = [ pkgs.kmod ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.kmod}/bin/modprobe nfsd";
      ExecStop = "${pkgs.kmod}/bin/modprobe -r nfsd";
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."nfs-server" = {
    autoStart = true;
    image = "ghcr.io/bspwr/nfs-server:latest";
    volumes = [
      "/ocean/nas/bree:/nas/bree"
      "/ocean/backup/overkill:/backup/overkill"
      "/ocean/images:/images"
    ];
    environment = {
      NFS_VERSION = "4.2";
      NFS_SERVER_THREAD_COUNT = "12";
      NFS_EXPORT_0 = "/nas/bree         192.168.69.69(rw,nohide,insecure,no_subtree_check) 100.64.0.0/10(rw,nohide,insecure,no_subtree_check)";
      NFS_EXPORT_2 = "/backup/overkill  192.168.69.69(rw,nohide,insecure,no_subtree_check,no_root_squash) 100.64.0.0/10(rw,nohide,insecure,no_subtree_check,no_root_squash)";
      NFS_EXPORT_3 = "/images           192.168.69.69(rw,nohide,insecure,no_subtree_check,no_root_squash) 100.64.0.0/10(rw,nohide,insecure,no_subtree_check,no_root_squash)";
    };
    dependsOn = [ "modprobe-nfs" "modprobe-nfsd" ];
    extraOptions = [
      # cap_add
      "--cap-add=SYS_ADMIN"
      # network_mode
      "--net=host"
    ];
  };

  # setup firewall for nfs
  networking.firewall = {
    allowedTCPPorts = [ 2049 ];
  };
}
