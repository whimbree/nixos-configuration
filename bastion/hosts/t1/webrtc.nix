{ lib, pkgs, vmName, mkVMNetworking, ... }:
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
        source = "/services/traefik/secrets";
        mountPoint = "/host-secrets";
        tag = "secrets";
        proto = "virtiofs";
        securityModel = "none";
      }
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

  # ACME for gaybottoms.org only (coturn TLS)
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "whimbree@pm.me";
      dnsProvider = "porkbun";
      credentialsFile = "/var/lib/acme/porkbun-credentials";
    };

    certs."gaybottoms.org" = {
      domain = "*.gaybottoms.org";
      extraDomainNames = [ "gaybottoms.org" ];
      dnsProvider = "porkbun";
      credentialsFile = "/var/lib/acme/porkbun-credentials";
    };
  };

  systemd.services.create-porkbun-credentials = {
    description = "Create Porkbun credentials file from secrets";
    before = [ "acme-gaybottoms.org.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      while [ ! -d /host-secrets ]; do
        echo "Waiting for host secrets to be mounted..."
        sleep 2
      done

      mkdir -p /var/lib/acme
      {
        echo "PORKBUN_API_KEY=$(cat /host-secrets/porkbun-api-key)"
        echo "PORKBUN_SECRET_API_KEY=$(cat /host-secrets/porkbun-secret-api-key)"
      } > /var/lib/acme/porkbun-credentials

      chmod 640 /var/lib/acme/porkbun-credentials

      echo "Porkbun credentials file created successfully"
    '';
  };

  # Coturn TURN/STUN server
  services.coturn = {
    enable = true;
    listening-port = 3478;
    tls-listening-port = 5349;

    cert = "/var/lib/acme/gaybottoms.org/fullchain.pem";
    pkey = "/var/lib/acme/gaybottoms.org/key.pem";

    use-auth-secret = true;
    static-auth-secret-file = "/host-secrets/coturn-secret";

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
    after = [ "acme-gaybottoms.org.service" ];
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
