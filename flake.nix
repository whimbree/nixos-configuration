{
  description = "Whimbree's NixOS Flake";

  inputs = {
    # Official NixOS package source
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    # Nix User Repository
    nur.url = "github:nix-community/NUR";
    # home-manager, used for managing user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, nur, ... }@inputs: {
    nixosConfigurations = {
      "megakill" = nixpkgs-unstable.lib.nixosSystem {
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
