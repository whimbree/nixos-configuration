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
    , ... }@inputs: {
      nixosConfigurations = {
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
          modules = [ microvm.nixosModules.host ./bastion/configuration.nix ];
        };
        "glados" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [
            microvm.nixosModules.microvm
            ./bastion/hosts/glados/configuration.nix
          ];
        };
        "wheatley" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs self; };
          modules = [ ./wheatley/configuration.nix ];
        };
      };
    };
}
