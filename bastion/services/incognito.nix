{ config, pkgs, lib, ... }: {
  systemd.services.docker-create-network-incognito = {
    enable = true;
    description = "Create incognito docker network";
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = pkgs.writeScript "docker-create-network-incognito" ''
        #! ${pkgs.runtimeShell} -e
        ${pkgs.docker}/bin/docker network create incognito || true
      '';
    };
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  virtualisation.oci-containers.containers."privoxyvpn-incognito" = {
    autoStart = true;
    image = "docker.io/binhex/arch-privoxyvpn:latest";
    volumes = [
      "/services/incognito/privoxyvpn:/config:Z"
      "/etc/localtime:/etc/localtime:ro"
    ];
    environment = {
      VPN_ENABLED = "yes";
      VPN_PROV = "custom";
      VPN_CLIENT = "wireguard";
      SOCKS_USER = "admin";
      SOCKS_PASS = "admin";
      ENABLE_SOCKS = "yes";
      ENABLE_PRIVOXY = "yes";
      LAN_NETWORK = "192.168.69.0/24,172.17.0.0/12,100.64.0.0/32";
      NAME_SERVERS = "84.200.69.80,37.235.1.174,1.1.1.1,37.235.1.177,84.200.70.40,1.0.0.1";
      PUID = "1420";
      PGID = "1420";
      TZ = "America/New_York";
    };
    ports = [
      "0.0.0.0:18089:18089" # Monerod
      # expose only locally
      "127.0.0.1:8118:8118" # Privoxy
      "127.0.0.1:9118:9118" # Microsocks
      # expose only to tailscale
      "100.64.0.2:4444:4444" # I2P HTTP Proxy
      "100.64.0.2:9150:9150" # Tor SOCKS Proxy
    ];
    dependsOn = [ "create-network-incognito" "modprobe-wireguard" ];
    extraOptions = [
      # privileged
      "--privileged"
      # sysctls
      "--sysctl"
      "net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl"
      "net.ipv6.conf.all.disable_ipv6=0"
      # networks
      "--network=incognito"
      # healthcheck
      "--health-cmd"
      "curl --fail https://checkip.amazonaws.com | grep 194.127.167 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "60"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      ## traefik
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=incognito"
      # quetre
      "--label"
      "traefik.http.routers.quetre.rule=Host(`quetre.bspwr.com`)"
      "--label"
      "traefik.http.routers.quetre.entrypoints=websecure"
      "--label"
      "traefik.http.routers.quetre.tls=true"
      "--label"
      "traefik.http.routers.quetre.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.quetre.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.quetre.service=quetre"
      "--label"
      "traefik.http.routers.quetre.middlewares=default@file"
      "--label"
      "traefik.http.services.quetre.loadbalancer.server.port=7070"
      # rimgo
      "--label"
      "traefik.http.routers.rimgo.rule=Host(`rimgo.bspwr.com`)"
      "--label"
      "traefik.http.routers.rimgo.entrypoints=websecure"
      "--label"
      "traefik.http.routers.rimgo.tls=true"
      "--label"
      "traefik.http.routers.rimgo.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.rimgo.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.rimgo.service=rimgo"
      "--label"
      "traefik.http.routers.rimgo.middlewares=default@file"
      "--label"
      "traefik.http.services.rimgo.loadbalancer.server.port=6060"
      # i2p http proxy (web console)
      "--label"
      "traefik.http.routers.i2p-http-proxy.rule=Host(`i2pconsole.local.bspwr.com`)"
      "--label"
      "traefik.http.routers.i2p-http-proxy.entrypoints=websecure"
      "--label"
      "traefik.http.routers.i2p-http-proxy.tls=true"
      "--label"
      "traefik.http.routers.i2p-http-proxy.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.i2p-http-proxy.tls.domains[0].main=*.local.bspwr.com"
      "--label"
      "traefik.http.routers.i2p-http-proxy.service=i2p-http-proxy"
      "--label"
      "traefik.http.routers.i2p-http-proxy.middlewares=local-allowlist@file, default@file"
      "--label"
      "traefik.http.services.i2p-http-proxy.loadbalancer.server.port=7657"
      # redlib
      "--label"
      "traefik.http.routers.redlib.rule=Host(`redlib.bspwr.com`)"
      "--label"
      "traefik.http.routers.redlib.entrypoints=websecure"
      "--label"
      "traefik.http.routers.redlib.tls=true"
      "--label"
      "traefik.http.routers.redlib.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.redlib.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.redlib.service=redlib"
      "--label"
      "traefik.http.routers.redlib.middlewares=default@file"
      "--label"
      "traefik.http.services.redlib.loadbalancer.server.port=8080"
      # dependheal
      "--label"
      "dependheal.enable=true"
    ];
  };

  virtualisation.oci-containers.containers."i2p-http-proxy" = {
    autoStart = true;
    image = "docker.io/geti2p/i2p";
    volumes = [
      "/services/incognito/i2pconfig:/i2p/.i2p"
      "/services/incognito/i2psnark:/i2psnark"
    ];
    dependsOn = [ "create-network-incognito" "privoxyvpn-incognito" ];
    extraOptions = [
      # network_mode
      "--net=container:privoxyvpn-incognito"
      # healthcheck
      # "--health-cmd"
      # "wget -qO- --no-verbose --tries=1 localhost:7657 || exit 1"
      # "--health-interval"
      # "10s"
      # "--health-retries"
      # "6"
      # "--health-timeout"
      # "2s"
      # "--health-start-period"
      # "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-incognito"
    ];
  };

  virtualisation.oci-containers.containers."tor-socks-proxy" = {
    autoStart = true;
    image = "docker.io/peterdavehello/tor-socks-proxy:latest";
    volumes = [
      "/services/incognito/bazincognito:/config:Z"
      "/ocean/media/movies:/movies:z"
      "/ocean/media/shows:/shows:z"
      "/ocean/downloads:/downloads:z"
    ];
    dependsOn = [ "create-network-incognito" "privoxyvpn-incognito" ];
    extraOptions = [
      # network_mode
      "--net=container:privoxyvpn-incognito"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 https://checkip.amazonaws.com | grep 194.127.167 || exit 1"
      "--health-interval"
      "20s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-incognito"
    ];
  };

  # vpn port opened: 56366
  virtualisation.oci-containers.containers."monerod" = {
    autoStart = true;
    image = "ghcr.io/whimbree/simple-monerod:v0.18.2.2";
    user = "1420:1420";
    volumes = [ "/ocean/services/monerod:/home/monero" ];
    cmd = [
      "--p2p-external-port=56366"
      "--rpc-restricted-bind-ip=0.0.0.0"
      "--rpc-restricted-bind-port=18089"
      "--no-igd"
      "--no-zmq"
      "--enable-dns-blocklist"
    ];
    dependsOn = [ "create-network-incognito" "privoxyvpn-incognito" ];
    extraOptions = [
      # network_mode
      "--net=container:privoxyvpn-incognito"
      # healthcheck
      "--health-cmd"
      "curl --fail http://localhost:18081/get_info || exit 1"
      "--health-interval"
      "20s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-incognito"
    ];
  };

  virtualisation.oci-containers.containers."redlib" = {
    autoStart = true;
    image = "quay.io/redlib/redlib:latest";
    dependsOn = [ "create-network-incognito" "privoxyvpn-incognito" ];
    extraOptions = [
      # network_mode
      "--net=container:privoxyvpn-incognito"
      # healthcheck
      "--health-cmd"
      "wget -qO- --no-verbose --tries=1 http://0.0.0.0:8080/settings || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-incognito"
    ];
  };

  virtualisation.oci-containers.containers."metube" = {
    autoStart = true;
    image = "ghcr.io/alexta69/metube:latest";
    volumes = [ "/ocean/downloads/metube:/metube" ];
    environment = {
      UID = "1420";
      GID = "1420";
      DOWNLOAD_DIR = "/metube";
    };
    dependsOn = [ "create-network-incognito" ];
    extraOptions = [
      # networks
      "--network=incognito"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=incognito"
      "--label"
      "traefik.http.routers.metube.rule=Host(`metube.bspwr.com`)"
      "--label"
      "traefik.http.routers.metube.entrypoints=websecure"
      "--label"
      "traefik.http.routers.metube.tls=true"
      "--label"
      "traefik.http.routers.metube.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.metube.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.metube.service=metube"
      "--label"
      "traefik.http.routers.metube.middlewares=default@file"
      "--label"
      "traefik.http.services.metube.loadbalancer.server.port=8081"
    ];
  };

  # virtualisation.oci-containers.containers."nitter" = {
  #   autoStart = true;
  #   image = "docker.io/zedeus/nitter:latest";
  #   volumes = [ "/services/incognito/nitter/nitter.conf:/src/nitter.conf:ro" ];
  #   dependsOn = [ "create-network-incognito" "nitter-redis" ];
  #   extraOptions = [
  #     # networks
  #     "--network=incognito"
  #     # healthcheck
  #     "--health-cmd"
  #     "wget -nv --tries=1 --spider http://127.0.0.1:8080/Jack/status/20 || exit 1"
  #     "--health-interval"
  #     "30s"
  #     "--health-retries"
  #     "5"
  #     "--health-timeout"
  #     "5s"
  #     # labels
  #     "--label"
  #     "traefik.enable=true"
  #     "--label"
  #     "traefik.docker.network=incognito"
  #     "--label"
  #     "traefik.http.routers.nitter.rule=Host(`nitter.bspwr.com`)"
  #     "--label"
  #     "traefik.http.routers.nitter.entrypoints=websecure"
  #     "--label"
  #     "traefik.http.routers.nitter.tls=true"
  #     "--label"
  #     "traefik.http.routers.nitter.tls.certresolver=porkbun"
  #     "--label"
  #     "traefik.http.routers.nitter.tls.domains[0].main=*.bspwr.com"
  #     "--label"
  #     "traefik.http.routers.nitter.service=nitter"
  #     "--label"
  #     "traefik.http.routers.nitter.middlewares=default@file"
  #     "--label"
  #     "traefik.http.services.nitter.loadbalancer.server.port=8080"
  #   ];
  # };

  virtualisation.oci-containers.containers."nitter-redis" = {
    autoStart = true;
    image = "docker.io/redis:6.2.5-alpine";
    cmd = [ "redis-server" "--save" "60" "1" "--loglevel" "warning" ];
    volumes = [ "/services/incognito/nitter-redis:/data" ];
    dependsOn = [ "create-network-incognito" "nitter-redis" ];
    extraOptions = [
      # networks
      "--network=incognito"
      # healthcheck
      "--health-cmd"
      "redis-cli ping"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
    ];
  };

  virtualisation.oci-containers.containers."quetre" = {
    autoStart = true;
    image = "ghcr.io/whimbree/quetre:latest";
    environment = {
      NODE_ENV = "production";
      PORT = "7070";
    };
    dependsOn = [ "create-network-incognito" "privoxyvpn-incognito" ];
    extraOptions = [
      # network_mode
      "--net=container:privoxyvpn-incognito"
      # healthcheck
      # "--health-cmd"
      # "wget -qO- --no-verbose --tries=1 localhost:7070 || exit 1"
      # "--health-interval"
      # "30s"
      # "--health-retries"
      # "5"
      # "--health-timeout"
      # "5s"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-incognito"
    ];
  };

  virtualisation.oci-containers.containers."rimgo" = {
    autoStart = true;
    image = "codeberg.org/video-prize-ranch/rimgo";
    environment = { PORT = "6060"; };
    dependsOn = [ "create-network-incognito" "privoxyvpn-incognito" ];
    extraOptions = [
      # network_mode
      "--net=container:privoxyvpn-incognito"
      # labels
      "--label"
      "dependheal.enable=true"
      "--label"
      "dependheal.parent=privoxyvpn-incognito"
    ];
  };

  virtualisation.oci-containers.containers."proxitok" = {
    autoStart = true;
    image = "ghcr.io/pablouser1/proxitok:master";
    environment = {
      LATTE_CACHE = "/cache";
      API_CACHE = "redis";
      REDIS_HOST = "proxitok-redis";
      REDIS_PORT = "6379";
      API_SIGNER = "remote";
      API_SIGNER_URL = "http://proxitok-signer:8080/signature";
      PROXY_HOST = "http://privoxyvpn-incognito";
      PROXY_PORT = "8118";
    };
    dependsOn =
      [ "create-network-incognito" "proxitok-redis" "proxitok-signer" ];
    extraOptions = [
      # networks
      "--network=incognito"
      # healthcheck
      "--health-cmd"
      "curl --fail localhost:8080 || exit 1"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=incognito"
      "--label"
      "traefik.http.routers.proxitok.rule=Host(`proxitok.bspwr.com`)"
      "--label"
      "traefik.http.routers.proxitok.entrypoints=websecure"
      "--label"
      "traefik.http.routers.proxitok.tls=true"
      "--label"
      "traefik.http.routers.proxitok.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.proxitok.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.proxitok.service=proxitok"
      "--label"
      "traefik.http.routers.proxitok.middlewares=default@file"
      "--label"
      "traefik.http.services.proxitok.loadbalancer.server.port=8080"
    ];
  };

  virtualisation.oci-containers.containers."proxitok-redis" = {
    autoStart = true;
    image = "docker.io/redis:7-alpine";
    cmd = [ "redis-server" "--save" "60" "1" "--loglevel" "warning" ];
    volumes = [ "/services/incognito/proxitok/redis:/data" ];
    dependsOn = [ "create-network-incognito" ];
    extraOptions = [
      # networks
      "--network=incognito"
      # healthcheck
      "--health-cmd"
      "redis-cli ping"
      "--health-interval"
      "10s"
      "--health-retries"
      "30"
      "--health-timeout"
      "10s"
      "--health-start-period"
      "10s"
    ];
  };

  virtualisation.oci-containers.containers."proxitok-signer" = {
    autoStart = true;
    image = "ghcr.io/pablouser1/signtok:master";
    dependsOn = [ "create-network-incognito" ];
    extraOptions = [
      # networks
      "--network=incognito"
    ];
  };

  virtualisation.oci-containers.containers."searxng" = {
    autoStart = true;
    image = "docker.io/searxng/searxng:latest";
    volumes = [ "/services/incognito/searxng:/etc/searxng" ];
    dependsOn = [ "create-network-incognito" ];
    extraOptions = [
      # cap_drop
      "--cap-drop=ALL"
      # cap_add
      "--cap-add=CHOWN"
      "--cap-add=SETGID"
      "--cap-add=SETUID"
      # networks
      "--network=incognito"
      # labels
      "--label"
      "traefik.enable=true"
      "--label"
      "traefik.docker.network=incognito"
      "--label"
      "traefik.http.routers.searxng.rule=Host(`search.bspwr.com`)"
      "--label"
      "traefik.http.routers.searxng.entrypoints=websecure"
      "--label"
      "traefik.http.routers.searxng.tls=true"
      "--label"
      "traefik.http.routers.searxng.tls.certresolver=porkbun"
      "--label"
      "traefik.http.routers.searxng.tls.domains[0].main=*.bspwr.com"
      "--label"
      "traefik.http.routers.searxng.service=searxng"
      "--label"
      "traefik.http.routers.searxng.middlewares=default@file"
      "--label"
      "traefik.http.services.searxng.loadbalancer.server.port=8080"
    ];
  };

  # TODO: fix
  # virtualisation.oci-containers.containers."searxng-redis" = {
  #   autoStart = true;
  #   image = "docker.io/redis:alpine";
  #   cmd = [ "redis-server" "--save" ''""'' "--appendonly" ''"no"'' ];
  #   dependsOn = [ "create-network-incognito" ];
  #   extraOptions = [
  #     # cap_drop
  #     "--cap-drop=ALL"
  #     # cap_add
  #     "--cap-add=SETGID"
  #     "--cap-add=SETUID"
  #     "--cap-add=DAC_OVERRIDE"
  #     # networks
  #     "--network=incognito"
  #     # tmpfs
  #     "--tmpfs"
  #     "/var/lib/redis"
  #   ];
  # };
}
