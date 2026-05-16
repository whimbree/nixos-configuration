{ pkgs, ... }: {

  # PulseAudio and Pipewire are mutually exclusive.
  services.pulseaudio.enable = false;

  # rtkit grants Pipewire real-time scheduling priority without running as root.
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true; # needed for 32-bit games / Wine
    pulse.enable = true;      # PulseAudio compatibility shim
    jack.enable = true;       # JACK compatibility shim (DAW / low-latency apps)

    # Low-latency configuration: 32-sample quantum at 48 kHz ≈ 0.67ms.
    # The quantum range (min/max) allows apps to negotiate up to 384 samples
    # (8ms) for battery-friendly playback while the default stays at 32.
    extraConfig.pipewire."92-low-latency" = {
      context.properties = {
        default.clock.rate = 48000;
        default.clock.quantum = 32;
        default.clock.min-quantum = 32;
        default.clock.max-quantum = 384;
      };
    };

    # Mirror the low-latency settings for apps using the PulseAudio backend.
    extraConfig.pipewire-pulse."92-low-latency" = {
      context.modules = [{
        name = "libpipewire-module-protocol-pulse";
        args = {
          pulse.min.req = "32/48000";
          pulse.default.req = "32/48000";
          pulse.max.req = "384/48000";
          pulse.min.quantum = "32/48000";
          pulse.max.quantum = "384/48000";
        };
      }];
      stream.properties = {
        node.latency = "32/48000";
        resample.quality = 1;
      };
    };

    # WirePlumber bluetooth codec configuration.
    # SBC-XQ: higher-quality SBC (wider bitpool, ~328 kbps vs ~328 kbps standard).
    # mSBC: wideband speech codec for headsets (16 kHz HFP instead of 8 kHz).
    # Headset roles: expose both headset (hfp_hf) and hands-free (hfp_ag) profiles
    # so the device can act as either side of a call.
    wireplumber.configPackages = [
      (pkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/51-bluez-config.lua" ''
        bluez_monitor.properties = {
          ["bluez5.enable-sbc-xq"] = true,
          ["bluez5.enable-msbc"] = true,
          ["bluez5.enable-hw-volume"] = true,
          ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
        }
      '')
    ];
  };

  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        # Enable A2DP source, sink, media, and socket profiles.
        Enable = "Source,Sink,Media,Socket";
      };
    };
  };
}
