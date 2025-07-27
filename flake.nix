{
  description = "Whimbree's NixOS Flake";

  inputs = {
    # Stable NixOS nixpkgs package set; pinned to the 24.11 release.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    # Tracks nixos/nixpkgs-channels unstable branch.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Nix User Repository
    nur.url = "github:nix-community/NUR";

    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    flake-utils.url = "github:numtide/flake-utils";

    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    btc-clients-nix = {
      url = "github:emmanuelrosa/btc-clients-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nur, microvm, btc-clients-nix
    , ... }@inputs: 
  let
    # Helper function for MicroVMs
    mkMicroVM = path: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs self; };
      modules = [
        microvm.nixosModules.microvm
        ./bastion/modules/microvm-defaults.nix  # Common VM config
        path
      ];
    };
    
    # Helper function for regular hosts
    mkHost = pkgs: path: pkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs self; };
      modules = [ path ];
    };
  in {
    nixosConfigurations = {
      # Physical hosts
      "megakill" = nixpkgs-unstable.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs self; };
        modules = [
          nur.modules.nixos.default
          ({ pkgs, ... }: {
            nixpkgs.overlays = [
              (final: prev: {
                # Only override specific packages
                bisq = btc-clients-nix.packages.${pkgs.system}.bisq;
              })
            ];
          })
          ./megakill/configuration.nix
        ];
      };
      
      "bastion" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs self; };
        modules = [ 
          microvm.nixosModules.host 
          ./bastion/configuration.nix 
        ];
      };
      
      "wheatley" = mkHost nixpkgs ./wheatley/configuration.nix;

      # Tier 0 - Infrastructure/DMZ
      "sni-proxy" = mkMicroVM ./bastion/hosts/t0/sni-proxy.nix;
      
      # Tier 1 - Low value, high risk
      # "jellyfin" = mkMicroVM ./bastion/hosts/t1/jellyfin.nix;
      # "sonarr" = mkMicroVM ./bastion/hosts/t1/sonarr.nix;
      # "radarr" = mkMicroVM ./bastion/hosts/t1/radarr.nix;
      # "prowlarr" = mkMicroVM ./bastion/hosts/t1/prowlarr.nix;
      # "delugevpn" = mkMicroVM ./bastion/hosts/t1/delugevpn.nix;
      
      # Tier 2 - Medium value
      # "home-assistant" = mkMicroVM ./bastion/hosts/t2/home-assistant.nix;
      
      # Tier 3 - High value, sensitive
      # "nextcloud" = mkMicroVM ./bastion/hosts/t3/nextcloud.nix;
      # "immich" = mkMicroVM ./bastion/hosts/t3/immich.nix;
      # "vaultwarden" = mkMicroVM ./bastion/hosts/t3/vaultwarden.nix;
      
      # Tier 4 - Critical infrastructure
      # "vpn-gateway" = mkMicroVM ./bastion/hosts/t4/vpn-gateway.nix;
      # "backup-server" = mkMicroVM ./bastion/hosts/t4/backup-server.nix;
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