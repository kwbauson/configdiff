{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-compat = {
    url = "github:NixOS/flake-compat";
    flake = false;
  };

  outputs = { self, nixpkgs, ... }:
    {
      packages = nixpkgs.lib.genAttrs
        nixpkgs.lib.systems.flakeExposed
        (system: {
          default = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {
            configdiffNix = self.outPath;
            configdiffAttr = "default";
          };
        });
    };
}
