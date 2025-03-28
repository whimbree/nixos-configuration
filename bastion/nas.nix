{ config, pkgs, lib, ... }: {
  # Note: when adding user do not forget to run `smbpasswd -a <USER>`.
  services.samba = {
    enable = true;
    openFirewall = true;
    securityType = "user";
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server role" = "standalone server";
        "dns proxy" = "no";
        "pam password change" = "yes";
        "map to guest" = "bad user";
        "usershare allow guests" = "yes";
        "create mask" = "0664";
        "force create mode" = "0664";
        "directory mask" = "0775";
        "force directory mode" = "0775";
        "follow symlinks" = "yes";
        "load printers" = "no";
        "printing" = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
        "strict locking" = "no";
        "aio read size" = "0";
        "aio write size" = "0";
        "vfs objects" = "acl_xattr catia streams_xattr";
        "inherit permissions" = "yes";
        # Security
        "client ipc max protocol" = "SMB3";
        "client ipc min protocol" = "SMB2_10";
        "client max protocol" = "SMB3";
        "client min protocol" = "SMB2_10";
        "server max protocol" = "SMB3";
        "server min protocol" = "SMB2_10";
      };
      public = {
        "path" = "/ocean/public";
        "browseable" = "yes";
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
        "path" = "/ocean/downloads";
        "browseable" = "yes";
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
        "path" = "/merged/media";
        "browseable" = "yes";
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
    nssmdns4 = true;
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

  # bind mount nfs share into export directory
  fileSystems."/export/nas/bree" = {
    device = "/ocean/nas/bree";
    options = [ "bind" ];
  };
  fileSystems."/export/backup/megakill" = {
    device = "/ocean/backup/megakill";
    options = [ "bind" ];
  };
  fileSystems."/export/backup/overkill" = {
    device = "/ocean/backup/overkill";
    options = [ "bind" ];
  };
  fileSystems."/export/images" = {
    device = "/ocean/images";
    options = [ "bind" ];
  };

  # enable nfs
  services.nfs.server = {
    enable = true;
    nproc = 12;
    exports = ''
      /export/nas/bree         192.168.69.69(rw,nohide,insecure,no_subtree_check) 100.64.0.0/24(rw,nohide,insecure,no_subtree_check)
      /export/backup/overkill  192.168.69.69(rw,nohide,insecure,no_subtree_check,no_root_squash) 100.64.0.0/24(rw,nohide,insecure,no_subtree_check,no_root_squash)
      /export/images           192.168.69.69(rw,nohide,insecure,no_subtree_check,no_root_squash) 100.64.0.0/24(rw,nohide,insecure,no_subtree_check,no_root_squash)
    '';
  };

  services.rpcbind.enable = true;

  # setup firewall for nfs
  networking.firewall = { allowedTCPPorts = [ 2049 ]; };
}
