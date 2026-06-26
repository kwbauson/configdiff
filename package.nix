{ lib
, writers
, pkgs
, runCommandLocal
, stdenv
, nix

  # required configuration
, configdiffNix
, configdiffNixAttr
, configdiffFlake ? configdiffNix
, configdiffFlakeAttr ? configdiffNixAttr

  # optional configuration
, skipPatterns ? [
    [ "_module" ]
    [ "assertions" ]
    [ "warnings" ]
    [ "home-manager" "extraSpecialArgs" ]
    [ "home-manager" "users" null "_module" ]
    [ "home-manager" "users" null "assertions" ]
    [ "home-manager" "users" null "warnings" ]
  ]
, skipDerivationAttrs ? [ "type" "outputName" "outputs" "meta" ]
}:
let
  inherit (lib)
    any isString concatMapStringsSep length foldl' fix zipLists toJSON init
    elem isAttrs mapAttrs isList imap optionalAttrs concatStringsSep
    hasAttrByPath getAttrFromPath setAttrByPath splitString optionalString flip
    seq trim concatMapAttrsStringSep isFunction readFile hasInfix hasAttr
    ;
  inherit (lib.generators) toPretty;
  inherit (lib.strings) escapeNixIdentifier;
  inherit (stdenv.hostPlatform) system;

  marker = "TRACE_CONFIG";
  traceMarker = "trace: ${marker}";
  internalMarker = "# NIX_INTERNAL";
  extraParser = /* python */ ''
    internal["self_nix"] = "${configdiffNix}"
    internal["self_nix_attr"] = "${configdiffNixAttr}"
    internal["self_flake"] = "${configdiffFlake}"
    internal["marker"] = "${traceMarker}"
  '';
  patched-modules-nix = runCommandLocal "patched-modules.nix" { } ''
    cp ${pkgs.path + "/lib/modules.nix"} $out
    patch $out ${./eval-modules-traced.patch}
  '';
  toPathStringPart = n: if isString n then escapeNixIdentifier n else "*";
  toPathString = path: concatMapStringsSep "." toPathStringPart path;
  pathMatches = path: pattern:
    length path == length pattern &&
    foldl' (acc: { fst, snd }: snd == null || fst == snd) true (zipLists path pattern);
  cleanForJSON = arg:
    if isAttrs arg then mapAttrs (_: cleanForJSON) arg
    else if isList arg then map cleanForJSON arg
    else if builtins.isFunction arg then "<function>"
    else arg;
  toJSON' = arg: toJSON (cleanForJSON arg);
  traceUsage = (f: f null null) (fix (cont': parent: at: info@{ label, path, args }: arg:
    let
      isDerivation = x: x ? outPath && x ? drvPath;
      inDerivation = isDerivation parent && !args.configJson or false;
      cont = at: cont' arg at (info // { path = path ++ [ at ]; });
      trace = p: x:
        let
          result =
            if args.configJson or false
            then [ p x ]
            else [ label (toPathString p) (toPretty { } x) ];
        in
        builtins.trace "${marker}${toJSON' result}" arg;
    in
    # FIXME probably want to move the non-trace logic into python
    if any (pathMatches path) skipPatterns then arg
    else if inDerivation && at == "outPath" then trace (init path) "<derivation ${arg}>"
    else if inDerivation && elem at skipDerivationAttrs then arg
    else if isAttrs arg then mapAttrs cont arg
    else if isList arg then imap (i: cont (i - 1)) arg
    else trace path arg
  ));
  tracedLib = lib: lib.extend (final: prev: {
    traceConfigUsage = config:
      let args = config._module.args; in
      if args ? _traceConfigUsage
      then traceUsage args._traceConfigUsage config
      else config;
    modules = import patched-modules-nix { lib = final; };
  });
  getLib = configuration: (configuration.extendModules {
    modules = [
      ({ lib, ... }: {
        _module.args._traceConfigUsage.lib = lib;
      })
    ];
  })._module.args._traceConfigUsage.lib;
  traceConfig = args: label:
    let
      configuration = args.${label};
      mkModule = path: {
        _module.args._traceConfigUsage = { inherit label path args; };
        _module.args.check = false;
      };
      mkNested = path: f: optionalAttrs
        (hasAttrByPath path configuration.options)
        (setAttrByPath path (f path (getAttrFromPath path configuration.config)));
      inherit (configuration.type.functor) payload;
    in
    ((tracedLib (getLib configuration)).evalModules {
      inherit (payload) class specialArgs;
      modules = payload.modules ++ [
        (args."${label}Module" or { })
        (mkModule [ ])
        (mkNested [ "home-manager" "users" ] (p: mapAttrs (n: _: mkModule (p ++ [ n ]))))
      ];
    }).config;
  indent = i: s: concatStringsSep "\n${i}" (splitString "\n" (trim s));
  buildFlake = inputs: outputsStr: runCommandLocal "source"
    {
      flakeNix = /* nix */ ''
        {
          inputs = {
            ${concatMapAttrsStringSep "\n    " (n: p: ''${n}.url = "path:${p}";'') inputs}
          };
          outputs = { self, ${concatMapAttrsStringSep ", " (n: _: n) inputs} }:
            ${indent "    " outputsStr};
        }
      '';
      nativeBuildInputs = [ nix.out ];
      passAsFile = [ "flakeNix" ];
    }
    ''
      export HOME=$PWD
      mkdir $out
      cd $out
      cp $flakeNixPath flake.nix
      nix --extra-experimental-features 'nix-command flakes' flake lock
    '';
  tryEvalOutput = cfg: config:
    if elem cfg.class or null [ "nixos" "darwin" ] then config.system.build.toplevel.outPath
    else if cfg.class or null == "homeManager" then config.home.activationPackage.outPath
    else if hasAttrByPath [ "meta" "nixvimInfo" ] cfg.options then config.build.package.outPath
    else throw "unknown configuration type, please pass `--eval PATH`";
  clearSubmodules = ref:
    if hasInfix "self.submodules = true;" (readFile (ref + "/flake.nix"))
    then
      runCommandLocal "without-submodules" { } ''
        cp -r ${ref} $out
        chmod -R +w $out
        # this is safe because we're only using flakes already in the store
        sed -Ei '/^\s*(inputs\.)?self\.submodules = true;$/d' $out/flake.nix
      ''
    else ref;
  mkFlake =
    { configdiff
    , old
    , new
    , oldOutput
    , newOutput
    , ...
    }@args:
    let
      setOutputString = ref: out: indent "    " /* nix */ ''
        ${ref} = ${ref}.outputs.${out} or
          ${ref}.outputs.packages.${system}.${out} or
          ${ref}.outputs.legacyPackages.${system}.${out};
      '';
      optionalRunArg = name: f: optionalString (hasAttr name args)
        "${name} = ${if isFunction f then f args.${name} else f};";
      passedArgs = [ "oldModule" "newModule" "configJson" ];
    in
    buildFlake (mapAttrs (_: clearSubmodules) { inherit configdiff old new; }) /* nix */ ''
      {
        traced = configdiff.packages.${system}.${configdiffFlakeAttr}.run {
          ${setOutputString "old" oldOutput}
          ${setOutputString "new" newOutput}
          ${indent "    " (concatMapStringsSep "\n" (x: optionalRunArg x (toPretty {})) passedArgs)}
          ${optionalRunArg "eval" (e: "_: c: c.${e}")}
        };
      }
    '';
  run = { old, new, configJson ? false, eval ? tryEvalOutput, ... }@args: foldl' (flip seq) "" [
    (if configJson then null else eval old (traceConfig args "old"))
    (eval new (traceConfig args "new"))
  ];
  runImpure =
    { type
    , label
    , path
    , ...
    }@args:
    let
      configuration = {
        nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
          modules = [ path ];
        };
        nix-darwin = import <darwin> {
          configuration = path;
        };
        home-manager = import <home-manager/modules> {
          configuration = path;
          pkgs = import <nixpkgs> { };
        };
      }.${type};
      traced = traceConfig (args // { ${label} = configuration; }) label;
      result =
        if args ? eval
        then getAttrFromPath (splitString "." args.eval) traced
        else tryEvalOutput configuration traced;
    in
    seq result "";
in
(writers.writePython3Bin "configdiff"
  {
    doCheck = false;
    libraries = ps: [ ps.termcolor ];
  }
  (lib.replaceString internalMarker extraParser (readFile ./main.py))
).overrideAttrs { passthru = { inherit mkFlake run runImpure patched-modules-nix; }; }
