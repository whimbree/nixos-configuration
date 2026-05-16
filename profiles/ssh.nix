{ ... }: {
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      # VERBOSE so SSH logins appear in the audit log.
      LogLevel = "VERBOSE";
    };
  };
}
