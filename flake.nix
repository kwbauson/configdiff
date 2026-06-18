{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-compat = {
    url = "github:NixOS/flake-compat";
    flake = false;
  };

  outputs = { self, nixpkgs, ... }:
    {
      packages = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (system: {
        default = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {
          configdiffNix = self.outPath;
          configdiffAttr = "default";
          # set configdiffFlake and configdiffFlakeAttr if they're different from above
        };
      });

      nixosConfigurations =
        let
          baseModule = { modulesPath, ... }: {
            imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];
            nixpkgs.pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
        in
        {
          base = nixpkgs.lib.nixosSystem { modules = [ baseModule ]; };
          hello = nixpkgs.lib.nixosSystem {
            modules = [
              baseModule
              ({ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; })
            ];
          };
        };

    };
}
