{ inputs, config, lib, pkgs, vmName, mkVMNetworking, ... }:
let
  vmLib = import ../../lib/vm-lib.nix { inherit lib; };
  vmConfig = vmLib.getAllVMs.${vmName};

  networking = mkVMNetworking {
    vmTier = vmConfig.tier;
    vmIndex = vmConfig.index;
  };

  # Port liquid's supervisor listens on inside the VM. The gateway proxies
  # https://liquid.bspwr.com here (through Anubis for the HTTP surface, and the
  # /ws WebSocket straight through).
  liquidPort = 3000;
in {
  # The liquid NixOS module (services.liquidagent), from the liquid flake input.
  imports = [ inputs.liquid.nixosModules.liquidagent ];

  microvm = {
    # An agent that builds and runs apps (Rust supervisor + Bun harness +
    # reviewer subagent + per-app Bun backends, plus on-VM builds) wants more
    # than the 1 vCPU / 1G a static web service needs.
    mem = 4096;
    hotplugMem = 8192;
    vcpu = 4;

    # Override the default volume set (tmpfs root + ssh-host-keys) with a single
    # persistent root: workspace git, the deployed worktree, SQLite, and per-app
    # databases must survive reboots, and a persistent root already holds the ssh
    # host keys. But mkForce also drops the sops age-key volume that
    # microvm-defaults adds for `sops = true` VMs, so re-declare it here (mirrors
    # microvm-defaults.nix) — otherwise /etc/sops has no backing device and its
    # fsType is undefined. Mounted read-only by label, so /dev/vdX order is moot.
    volumes = lib.mkForce [
      {
        image = "root.img";
        mountPoint = "/";
        size = 1024 * 50; # 50GB
        fsType = "ext4";
        autoCreate = true;
      }
      {
        image = "/persist/etc/sops/vm-keys/${vmName}.img";
        mountPoint = "/etc/sops";
        label = "sops-${vmName}";
        fsType = "ext4";
        size = 16;
        autoCreate = false;
        readOnly = true;
      }
    ];
  };

  # mkOverride 10 beats the mkForce (priority 50) tmpfs root in microvm-defaults.nix
  fileSystems."/" = lib.mkOverride 10 {
    device = "/dev/vda";
    fsType = "ext4";
  };

  networking.hostName = vmConfig.hostname;
  microvm.interfaces = networking.interfaces;
  systemd.network.networks."10-eth" = networking.networkConfig;

  # claude-code (the binary the agent harness drives) is unfree.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  # nix-ld provides /lib64/ld-linux-x86-64.so.2 so prebuilt npm binaries
  # (esbuild, better-sqlite3, sharp, …) pulled by agent-generated app backends
  # can run on NixOS. The base toolchain covers apps that need to compile.
  programs.nix-ld.enable = true;
  # claude-code so `claude login` is on PATH for the one-time subscription auth.
  environment.systemPackages = with pkgs; [ claude-code nodejs_22 python3 gnumake gcc ];

  # Initial login password from sops (secrets/bastion/liquidagent.yaml), rendered
  # into a root-only EnvironmentFile as LIQUID_INITIAL_PASSWORD — never in the nix
  # store. liquid seeds it only if no password is set yet; change it from the UI
  # after first login and this stops mattering.
  sops.secrets."liquid_initial_password" = { };
  sops.templates."liquid-env".content = ''
    LIQUID_INITIAL_PASSWORD=${config.sops.placeholder."liquid_initial_password"}
  '';

  services.liquidagent = {
    enable = true;
    # Reached from the gateway VM, so bind the interface rather than localhost.
    # Only the port below is open, and only the gateway routes to this tier.
    host = "0.0.0.0";
    port = liquidPort;
    # Reviewer gates app changes before they go live. Switchable live from the shell.
    pipelineMode = "reviewed";
    environmentFile = config.sops.templates."liquid-env".path;
  };

  # Only ssh (admin) and the liquid port (gateway proxy target) are reachable.
  networking.firewall.allowedTCPPorts = [ 22 liquidPort ];
}
