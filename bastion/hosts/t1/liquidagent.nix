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

    # Writable /nix/store overlay so the agent can build/install inside the VM
    # (the software-factory point): the read-only host store stays the lower
    # layer, this path is the writable upper. Setting it auto-enables the
    # nix-daemon (see nix.enable below).
    writableStoreOverlay = "/nix/.rw-store";

    # Persistent volumes, appended to microvm-defaults' set (ssh-host-keys + the
    # sops age-key volume) — a plain list, no mkForce, so those stay intact. Each
    # is found by label, so /dev/vdX order doesn't matter (microvm mkfs's
    # autoCreated volumes with their label).
    volumes = [
      {
        # Root: workspace git, deployed worktree, SQLite, per-app DBs, Claude creds.
        image = "root.img";
        mountPoint = "/";
        label = "nixos-root";
        size = 1024 * 50; # 50GB
        fsType = "ext4";
        autoCreate = true;
      }
      {
        # Writable upper layer for the /nix/store overlay (the agent's nix builds).
        image = "nix-store.img";
        mountPoint = "/nix/.rw-store";
        label = "nix-rw";
        size = 1024 * 64; # 64GB — grows with what's built in-VM; GC manually
        fsType = "ext4";
        autoCreate = true;
      }
    ];
  };

  # microvm-defaults forces "/" to tmpfs (mkForce, prio 50); override that with a
  # higher-priority def pointing at the labeled persistent root.
  fileSystems."/" = lib.mkOverride 10 {
    device = "/dev/disk/by-label/nixos-root";
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

  # microvm-defaults disables nix for stateless VMs; the factory VM needs it. The
  # writable store overlay above makes /nix/store writable — enable the daemon +
  # flakes and trust the service/admin accounts so the agent can build.
  nix.enable = true; # overrides microvm-defaults' `nix.enable = mkDefault false`
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "admin" "liquidagent" ];

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
    # Self-update: every 5 min the VM builds the latest liquid from GitHub (using
    # its writable /nix/store) and restarts only if it changed. Decoupled from
    # this flake's pinned input — that pin is now just the first-boot seed.
    autoUpdate.enable = true;
  };

  # Only ssh (admin) and the liquid port (gateway proxy target) are reachable.
  networking.firewall.allowedTCPPorts = [ 22 liquidPort ];
}
