{
  description = "Whimbree's NixOS Flake";

  inputs = {
    # Stable NixOS nixpkgs package set; pinned to the 23.11 release.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    # Tracks nixos/nixpkgs-channels unstable branch.
    #
    # Try to pull new/updated packages from 'unstable' whenever possible, as
    # these will likely have cached results from the last successful Hydra
    # jobset.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Tracks nixos/nixpkgs main branch.
    #
    # Only pull from 'trunk' when channels are blocked by a Hydra jobset
    # failure or the 'unstable' channel has not otherwise updated recently for
    # some other reason.
    trunk.url = "github:nixos/nixpkgs";
    # Nix User Repository
    nur.url = "github:nix-community/NUR";
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, trunk, nur, ... }@inputs:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [
          # Inject 'unstable' and 'trunk' into the overridden package set, so that
          # the following overlays may access them (along with any system configs
          # that wish to do so).
          (final: prev: {
            unstable = import nixpkgs-unstable {
              system = prev.system;
              config = prev.config;
            };
            trunk = import trunk {
              system = prev.system;
              config = prev.config;
            };
          })
        ];
      };
    in {
      nixosConfigurations = {
        "megakill" = nixpkgs.lib.nixosSystem {
          inherit pkgs;
          system = "x86_64-linux";
          modules = [ nur.nixosModules.nur ./megakill/configuration.nix ];
        };
        "bastion" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./bastion/configuration.nix ];
        };
        "wheatley" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./wheatley/configuration.nix ];
        };
      };
    };
}
