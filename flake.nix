{
  description = "Whimbree's NixOS Flake";

  inputs = {
    # Tracks nixos/nixpkgs-channels unstable branch.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Nix User Repository
    # nur = {
    #   url = "github:nix-community/NUR";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    btc-clients-nix = {
      url = "github:emmanuelrosa/btc-clients-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, microvm, btc-clients-nix, ... }@inputs:
    let
      # Helper function for MicroVMs
      mkMicroVM = path:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs self;
            vmName = nixpkgs.lib.removeSuffix ".nix"
              (builtins.baseNameOf path);
          };
          modules = [
            microvm.nixosModules.microvm
            ./bastion/modules/microvm-defaults.nix # Common VM config
            path
          ];
        };

      # Helper function for regular hosts
      mkHost = nixpkgs: modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = modules;
        };
    in {
      nixosConfigurations = {
        # Physical hosts

        "megakill" = mkHost nixpkgs [
          # nur.modules.nixos.default
          ({ pkgs, ... }: {
            nixpkgs.overlays = [
              (final: prev: {
                # Only override specific packages
                bisq = btc-clients-nix.packages.${pkgs.system}.bisq;
              })
            ];
          })
          ./megakill/configuration.nix
          ./modules/lix.nix
        ];

        # "megakill" = nixpkgs.lib.nixosSystem {
        #   system = "x86_64-linux";
        #   specialArgs = { inherit inputs self; };
        #   modules = [
        #     # nur.modules.nixos.default
        #     ({ pkgs, ... }: {
        #       nixpkgs.overlays = [
        #         (final: prev: {
        #           # Only override specific packages
        #           bisq = btc-clients-nix.packages.${pkgs.system}.bisq;
        #         })
        #       ];
        #     })
        #     ./megakill/configuration.nix
        #     ./modules/lix.nix
        #   ];
        # };

        "bastion" = mkHost nixpkgs [
          microvm.nixosModules.host
          ./bastion/configuration.nix
        ];

        # "bastion" = nixpkgs.lib.nixosSystem {
        #   system = "x86_64-linux";
        #   specialArgs = { inherit inputs self; };
        #   modules = [ microvm.nixosModules.host ./bastion/configuration.nix ];
        # };

        "wheatley" = mkHost nixpkgs [ ./wheatley/configuration.nix ];

        # Tier 0 - Infrastructure/DMZ (exposed, hardened)
        "gateway" = mkMicroVM ./bastion/hosts/t0/gateway.nix;

        # Tier 1 - Low value, high risk (untrusted workloads)
        "airvpn-sweden" = mkMicroVM ./bastion/hosts/t1/airvpn-sweden.nix;
        "airvpn-usa" = mkMicroVM ./bastion/hosts/t1/airvpn-usa.nix;

        # Tier 2 - Medium value (personal but not critical)
        "jellyfin" = mkMicroVM ./bastion/hosts/t2/jellyfin.nix;

        # Tier 3 - High value, sensitive
        "immich" = mkMicroVM ./bastion/hosts/t3/immich.nix;
        "nextcloud" = mkMicroVM ./bastion/hosts/t3/nextcloud.nix;
        "photoprism" = mkMicroVM ./bastion/hosts/t3/photoprism.nix;
        "syncthing" = mkMicroVM ./bastion/hosts/t3/syncthing.nix;
      };

      # Helper scripts for easier deployment
      # apps.x86_64-linux = {
      #   # Deploy all VMs
      #   deploy-all = {
      #     type = "app";
      #     program = toString (nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy-all" ''
      #       #!/bin/bash
      #       echo "Deploying bastion host..."
      #       nixos-rebuild switch --flake .#bastion --target-host bastion

      #       echo "Deploying all VMs..."
      #       for vm in sni-proxy jellyfin sonarr radarr prowlarr delugevpn nextcloud immich; do
      #         echo "Building $vm..."
      #         nixos-rebuild switch --flake .#$vm
      #       done
      #     '');
      #   };

      #   # Deploy by tier
      #   deploy-t1 = {
      #     type = "app";
      #     program = toString (nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy-t1" ''
      #       #!/bin/bash
      #       for vm in jellyfin sonarr radarr prowlarr delugevpn; do
      #         echo "Building $vm..."
      #         nixos-rebuild switch --flake .#$vm
      #       done
      #     '');
      #   };

      #   deploy-t3 = {
      #     type = "app";
      #     program = toString (nixpkgs.legacyPackages.x86_64-linux.writeScript "deploy-t3" ''
      #       #!/bin/bash
      #       for vm in nextcloud immich vaultwarden; do
      #         echo "Building $vm..."
      #         nixos-rebuild switch --flake .#$vm
      #       done
      #     '');
      #   };
      # };
    };
}
