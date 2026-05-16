{ ... }: {
  nix.gc = {
    automatic = true;
    randomizedDelaySec = "15m";
    options = "--delete-older-than 60d";
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Build in an isolated environment; catches missing dependencies early.
  nix.settings.sandbox = true;

  nixpkgs.config.allowUnfree = true;

  services.sysstat.enable = true;

  # Kill stuck services after 30s instead of the 90s default.
  systemd.settings.Manager.DefaultTimeoutStopSec = "30s";

  # Prevent git "dubious ownership" errors when nixos-rebuild runs git as root
  # against /etc/nixos (owned by bree via the /persist bind mount).
  environment.etc."gitconfig".text = ''
    [safe]
      directory = /etc/nixos
  '';
}
