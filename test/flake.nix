{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nixvim.url = "github:nix-community/nixvim";
  };
  outputs =
    { self
    , nixpkgs
    , home-manager
    , nix-darwin
    , nixvim
    }:
    let
      minimalNixosModule = { modulesPath, ... }: {
        imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
        nixpkgs.pkgs = nixpkgs.legacyPackages.x86_64-linux;
      };
    in
    {
      nixosConfigurations = {
        minimal = nixpkgs.lib.nixosSystem {
          modules = [ minimalNixosModule ];
        };
        postgresql = nixpkgs.lib.nixosSystem {
          modules = [
            minimalNixosModule
            { services.postgresql.enable = true; }
          ];
        };
      };

      homeConfigurations = { };
    };
}
