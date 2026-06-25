{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-compat = {
    url = "github:NixOS/flake-compat";
    flake = false;
  };

  outputs = { self, nixpkgs, ... }:
    {
      packages = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          configdiff = pkgs.callPackage ./package.nix {
            configdiffNix = self.outPath;
            configdiffNixAttr = "default";
            # set configdiffFlake and configdiffFlakeAttr if they're different from above
          };
        in
        rec {
          inherit configdiff;
          default = configdiff;
          ci-env = pkgs.buildEnv {
            name = "ci-env";
            paths = [ configdiff pkgs.ripgrep pkgs.ansifilter ];
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
