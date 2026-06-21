{ config, lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  livekitVersion = "v1.9.11";
in {
  microvm = {
    mem = 1024;
    hotplugMem = 2048;
    vcpu = 2;

    shares = [
      {
        source = "/services/fluxer/config";
        mountPoint = "/fluxer-config";
        tag = "fluxer-config";
        proto = "virtiofs";
        securityModel = "none";
      }
    ];

    volumes = [
      {
        image = "acme-certs.img";
        mountPoint = "/var/lib/acme";
        size = 1024;
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        size = 1024 * 2;
        fsType = "ext4";
        autoCreate = true;
      }
      # The sops age-key volume (/etc/sops) is added automatically by
      # microvm-defaults.nix because webrtc has `sops = true` in vm-registry.nix.
    ];
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Secrets via sops-nix. The age-key volume, defaultSopsFile
  # (secrets/bastion/webrtc.yaml), useSystemdActivation and age.keyFile are all
  # wired by microvm-defaults.nix (gated on `sops = true` in vm-registry.nix).
  # Here we only declare the secrets and templates this VM consumes.
  sops = {
    secrets."porkbun-api-key" = { };
    secrets."porkbun-secret-api-key" = { };
    # coturn reads this directly in its preStart (which runs as turnserver), so
    # own it by turnserver. useSystemdActivation orders sops-install-secrets after
    # user creation, so the turnserver user exists before this is chowned.
    secrets."coturn-secret" = { owner = "turnserver"; };
    # ACME wants an EnvironmentFile with PORKBUN_* vars; render one from the
    # two secrets. systemd reads EnvironmentFile as root, so default 0400 root
    # ownership is fine.
    templates."porkbun-credentials".content = ''
      PORKBUN_API_KEY=${config.sops.placeholder."porkbun-api-key"}
      PORKBUN_SECRET_API_KEY=${config.sops.placeholder."porkbun-secret-api-key"}
    '';
  };

  # ACME for gaybottoms.org only (coturn TLS)
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "whimbree@pm.me";
      dnsProvider = "porkbun";
      environmentFile = config.sops.templates."porkbun-credentials".path;
    };

    certs."gaybottoms.org" = {
      domain = "*.gaybottoms.org";
      extraDomainNames = [ "gaybottoms.org" ];
      dnsProvider = "porkbun";
      environmentFile = config.sops.templates."porkbun-credentials".path;
    };
  };

  # Coturn TURN/STUN server
  services.coturn = {
    enable = true;
    listening-port = 3478;
    tls-listening-port = 5349;

    cert = "/var/lib/acme/gaybottoms.org/fullchain.pem";
    pkey = "/var/lib/acme/gaybottoms.org/key.pem";

    use-auth-secret = true;
    # sops-install-secrets decrypts /run/secrets/coturn-secret (owned turnserver)
    # before coturn's preStart reads it via static-auth-secret-file.
    static-auth-secret-file = config.sops.secrets."coturn-secret".path;

    realm = "turn.gaybottoms.org";

    min-port = 50000;
    max-port = 51999;

    no-tcp-relay = false;
    extraConfig = ''
      denied-peer-ip=10.0.0.0-10.255.255.255
      denied-peer-ip=172.16.0.0-172.31.255.255
      denied-peer-ip=192.168.0.0-192.168.255.255
      denied-peer-ip=127.0.0.0-127.255.255.255
      denied-peer-ip=::1
      denied-peer-ip=fe80::-febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      denied-peer-ip=fc00::-fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
      fingerprint
      no-cli
      no-multicast-peers
      log-file=stdout
      simple-log
    '';
  };
  systemd.services.coturn = {
    after = [ "acme-gaybottoms.org.service" "sops-install-secrets.service" ];
    wants = [ "acme-gaybottoms.org.service" ];
  };
  systemd.services.coturn.preStart = lib.mkAfter ''
    IP=$(${pkgs.dnsutils}/bin/dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]')
    if [[ -n "$IP" ]]; then
      echo "external-ip=$IP" >> /run/coturn/turnserver.cfg
    fi
  '';

  # LiveKit server (host networking to avoid double-NAT for UDP media traffic)
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      livekit = {
        autoStart = true;
        image = "docker.io/livekit/livekit-server:${livekitVersion}";
        volumes =
          [ "/fluxer-config/livekit.yaml:/etc/livekit/livekit.yaml:ro" ];
        cmd = [ "--config" "/etc/livekit/livekit.yaml" ];
        # ports = [
        #   "0.0.0.0:7880:7880"
        #   "0.0.0.0:7881:7881/tcp"
        #   "0.0.0.0:52000-53999:52000-53999/udp"
        # ];
        extraOptions = [ "--network=host" ];
      };
    };
  };

  # Restart coturn when external IP changes
  systemd.services.coturn-ip-watcher = {
    description = "Restart coturn if external IP changes";
    after = [ "network-online.target" "coturn.service" ];
    wants = [ "network-online.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      IP=$(${pkgs.dnsutils}/bin/dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | ${pkgs.coreutils}/bin/tr -d '[:space:]') || true

      if [[ ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Could not determine public IP" >&2
        exit 0
      fi

      CURRENT=$(${pkgs.gnugrep}/bin/grep -oP 'external-ip=\K.*' /run/coturn/turnserver.cfg 2>/dev/null) || true

      if [[ "$IP" != "$CURRENT" ]]; then
        echo "IP changed ($CURRENT -> $IP), restarting coturn"
        ${pkgs.systemd}/bin/systemctl restart coturn.service
      fi
    '';
  };

  systemd.timers.coturn-ip-watcher = {
    description = "Check for external IP changes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitInactiveSec = "30s";
      AccuracySec = "5s";
    };
  };

  # SSH, STUN/TURN (3478, 5349), LiveKit signaling (7880) + ICE (7881)
  # UDP range: coturn relay (50000-51999) + LiveKit RTP media (52000-53999)
  networking.firewall = {
    allowedTCPPorts = [ 22 3478 5349 7880 7881 ];
    allowedUDPPorts = [ 3478 5349 ];
    allowedUDPPortRanges = [{
      from = 50000;
      to = 53999;
    }];
  };
}
