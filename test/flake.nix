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
    {
      nixosConfigurations =
        let
          baseModule = { modulesPath, ... }: {
            imports = [ ./nixos/configuration.nix ];
            nixpkgs.pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
        in
        {
          base = nixpkgs.lib.nixosSystem { modules = [ baseModule ]; };
          postgresql = nixpkgs.lib.nixosSystem {
            modules = [
              baseModule
              { services.postgresql.enable = true; }
            ];
          };
          home-manager = nixpkgs.lib.nixosSystem {
            modules = [
              baseModule
              home-manager.nixosModules.default
              {
                users.users.foo.isNormalUser = true;
                home-manager.users.foo = {
                  home.stateVersion = "26.05";
                  programs.git.enable = true;
                };
              }
            ];
          };
        };

      homeConfigurations =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          baseModule = ./home-manager/home.nix;
        in
        {
          base = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ baseModule ];
          };
          git = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              baseModule
              { programs.git.enable = true; }
            ];
          };
        };

      darwinConfigurations =
        let
          baseModule = {
            import = [ ./nix-darwin/configuration.nix ];
            nixpkgs.pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          };
        in
        {
          base = nix-darwin.lib.darwinSystem { modules = [ baseModule ]; };
          dnsmasq = nix-darwin.lib.darwinSystem {
            modules = [
              baseModule
              { services.dnsmasq.enable = true; }
            ];
          };
        };

      nixvimConfigurations = {
        base = nixvim.lib.evalNixvim { system = "x86_64-linux"; };
        ty = nixvim.lib.evalNixvim {
          system = "x86_64-linux";
          modules = [{ lsp.servers.ty.enable = true; }];
        };
      };
    };
}
