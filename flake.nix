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
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nur, ... }@inputs:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [
          # Inject 'unstable' into the overridden package set, so that
          # the following overlays may access them (along with any system configs
          # that wish to do so).
          (final: prev: {
            unstable = import nixpkgs {
              system = prev.system;
              config = prev.config;
            };
          })
        ];
      };
    in {
      nixosConfigurations = {
        "megakill" = nixpkgs-unstable.lib.nixosSystem {
          # inherit pkgs;
          system = "x86_64-linux";
          modules = [ nur.modules.nixos.default ./megakill/configuration.nix ];
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
