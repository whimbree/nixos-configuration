# Desktop wrapper around the official Keychron Launcher web app.
# Keychron does not ship a native Linux client; launcher.keychron.com is the
# supported configurator (WebHID, Chromium-only). This package opens it in
# Chromium --app mode so it appears as its own window/launcher entry.
{
  lib,
  symlinkJoin,
  writeShellApplication,
  makeDesktopItem,
  chromium,
}:

let
  launcher = writeShellApplication {
    name = "keychron-launcher";
    runtimeInputs = [ chromium ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/keychron-launcher"
      mkdir -p "$config_dir"
      exec chromium \
        --user-data-dir="$config_dir" \
        --class=KeychronLauncher \
        --app=https://launcher.keychron.com \
        "$@"
    '';
  };

  desktop = makeDesktopItem {
    name = "keychron-launcher";
    desktopName = "Keychron Launcher";
    genericName = "Keyboard Configurator";
    comment = "Configure Keychron keyboards";
    exec = "keychron-launcher";
    icon = "input-keyboard";
    categories = [
      "Settings"
      "HardwareSettings"
    ];
    startupNotify = true;
    # Chromium --app windows on Wayland/X11 report this WM class.
    startupWMClass = "chrome-launcher.keychron.com__-Default";
  };
in
symlinkJoin {
  name = "keychron-launcher";
  paths = [
    launcher
    desktop
  ];
  meta = {
    description = "Desktop wrapper for the official Keychron Launcher web app";
    homepage = "https://launcher.keychron.com/";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "keychron-launcher";
  };
}
