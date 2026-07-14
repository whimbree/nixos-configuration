{ config, lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  forgejoIP = vmLib.getAllVMs.forgejo.ip;
in {
  microvm = {
    mem = 8192;
    hotplugMem = 8192;
    vcpu = 8;

    volumes = [
      {
        # Persists the runner's registration (.runner file) and job caches.
        # The service runs with DynamicUser + StateDirectory=gitea-runner, so
        # the real path is under /var/lib/private. Deliberately a volume, not
        # a rpool/safe/microvms dataset: volumes live on microvm-runtime,
        # which znapzend doesn't snapshot — this state is disposable (worst
        # case: re-register the runner), same category as ssh-host-keys.img.
        image = "runner-state.img";
        mountPoint = "/var/lib/private/gitea-runner";
        size = 1024;
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "containers-cache.img";
        mountPoint = "/var/lib/containers";
        size = 1024 * 40;
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

  # Secrets via sops-nix (age-key volume + defaultSopsFile wired by
  # microvm-defaults.nix, gated on `sops = true` in vm-registry.nix).
  # forgejo-runner-token: registration token generated in the Forgejo UI
  # (Site administration -> Actions -> Runners -> Create registration token).
  sops = {
    secrets."forgejo-runner-token" = { };
    # The module wants an EnvironmentFile with TOKEN=<registration token>.
    templates."forgejo-runner-token-env".content = ''
      TOKEN=${config.sops.placeholder."forgejo-runner-token"}
    '';
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.default = {
      enable = true;
      name = vmConfig.hostname;
      # Direct to the forgejo VM; T1->T3 is blocked by default, so bastion's
      # networking.nix punches this one hole (runner -> forgejo:3000).
      url = "http://${forgejoIP}:3000";
      tokenFile = config.sops.templates."forgejo-runner-token-env".path;
      labels = [
        # GitHub-Actions-compatible fat image for ubuntu-latest workflows
        "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest"
        # Slim default recommended by Forgejo docs
        "docker:docker://code.forgejo.org/oci/node:22-bookworm"
        # Run directly on this VM's NixOS (module provides default hostPackages)
        "native:host"
      ];
      settings = {
        # 8 vcpus; let two jobs run concurrently
        runner.capacity = 2;
      };
    };
  };

  # Job containers pull images and fetch actions from the internet; the runner
  # itself only dials out (to forgejo + registries), so no inbound ports.
  networking.firewall.allowedTCPPorts = [ 22 ];
}
