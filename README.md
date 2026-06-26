# configdiff

Diff how options are used between arbitrary nixos/home-manager/etc
configurations in nix flakes

Huge shout out to
[oddlama/nixos-config-tui](https://github.com/oddlama/nixos-config-tui) and
their wonderful [blog
post](https://oddlama.org/blog/tracking-options-in-nixos/)!! They were the
inspiration for me to hack this together. This tool is like a much simpler
version of that project, and only the diff functionality.

## Usage

```
$ configdiff --usage
usage: configdiff [OPTIONS] ARGS [-- NIX_ARGS]

diff how nixpkgs lib.evalModules gets used between configurations

examples:
    configdiff {new,old}#nixosConfigurations.machine
    configdiff flake#nixosConfigurations.{machine,other}
    configdiff ~/flake-repo{?ref=HEAD,}#nixosConfigurations.machine

    configdiff flake#nixosConfigurations.machine -- --override-input new/nixpkgs nixpkgs/nixos-unstable-small
    configdiff flake#nixosConfigurations.machine --new-module '{ services.postgresql.enable = true; }'
    configdiff flake#darwinConfigurations.machine --new-module '{ services.dnsmasq.enable = true; }'
    configdiff flake#homeConfigurations.user --new-module '{ programs.git.enable = true; }'
    configdiff flake#nixvimConfiguration --new-module '{ lsp.servers.ty.enable = true; }'

    configdiff {/run/current-system,/etc/nixos}/configuration.nix
    configdiff /etc/nixos/configuration.nix --new-include nixpkgs=https://channels.nixos.org/nixos-unstable-small/nixexprs.tar.xz

    configdiff --config-json flake#nixosConfigurations.machine | jless
```

As long as you're using flakes, you can run this directly on your
configurations:

```bash
nix run github:kwbauson/configdiff old#nixosConfigurations.machine new#nixosConfigurations.machine
# or with bash's handy brace expansion
nix run github:kwbauson/configdiff {old,new}#nixosConfigurations.machine
```

This has to evaluate (but not build, so it also works across platforms) both
configurations, so it could take awhile (on my machine when I have all of the
flake inputs fetched already, it takes ~20 seconds).

There are a variety of test configurations you can try out in
[test/flake.nix](test/flake.nix) which get ci tested in
[checks.yml](.github/workflows/checks.yml). For example, to see what gets
changed when you enable postgreql on the nixos minimal iso:

```bash
nix run github:kwbauson/configdiff github:kwbauson/configdiff?dir=test#nixosConfigurations.{base,postgresql}
```

<img width="1249" height="439" alt="image" src="https://github.com/user-attachments/assets/a3782850-2482-44ea-a0fd-17f44ff02702" />

Arguments after `--` are passed directly to `nix`, allowing you to override
inputs in the `old` and `new` flakes:

```bash
# what changed in the minimal iso between major releases
nix run github:kwbauson/configdiff -- \
    github:kwbauson/configdiff?dir=test#nixosConfigurations.base{,} -- \
    --override-input old/nixpkgs nixpkgs/nixos-25.11 --override-input new/nixpkgs nixpkgs/nixos-26.05
```

You can pass the text of a module that gets injected into the configuration
with `--new-module` or `--old-module`. When either of those are passed, new
defaults to old, so you only have to pass one flake:

```bash
nix run github:kwbauson/configdiff -- \
    github:kwbauson/configdiff?dir=test#nixosConfigurations.base --new-module '{ services.postgresql.enable = true; }'
```

By default, the hash parts of nix store paths aren't considered as potential
changes, since showing them can be pretty noisy and often isn't very
informative. To include those hashes in the diff, you can pass `-i` or
`--include-hashes`:

```bash
nix run github:kwbauson/configdiff -- \
    -i github:kwbauson/configdiff?dir=test#nixosConfigurations.{base,postgresql}
```

By default `configdiff` can handle nixos, home-manager, nix-darwin, and nixvim
configurations. To diff other configuration types, pass the `--eval` flag with
a nix attribute path from `configuration.config` that when evaluated forces the
evaluation of the system. For example, if nixos wasn't built in, you could pass
`--eval system.build.toplevel.outPath`. Note that because nix is lazy, the
`outPath` part is important. `--eval` can also be used to "focus" the diff,
e.g. to see what's adding to `PATH` you could pass `--eval
system.path.outPath`.

## Why this new thing

When I saw
[oddlama/nixos-config-tui](https://github.com/oddlama/nixos-config-tui) I knew
it was something I'd always wanted, but sadly it looks like it hasn't had
changes since the initial burst of activity, and my rust-foo is sorely lacking.
I wanted to see if I could make something simpler, and perhaps with that
simplicity be able to get by without patching `nix` or `nixpkgs`.

`configdiff` is pretty simple. The combined nix+python code is less than 500
lines, so hopefully it's easy to understand what's going on and make any
changes you want. It should also work no matter what nixpkgs you use, so long
as `evalModules` isn't radically different.

## Limitations

Because this works by reading the stderr of `nix` while it's evaluating, I
don't think there's a way include a trace dump of your system's build without
double evaluating during build time. This means diffing has to fully evaluate
both old and new configurations, which is hefty.

`configdiff` needs to know how to reference itself, both as a flake output and
through a non-flake nix file. See the `callPackage` invocation in `flake.nix`
to override those. It uses that to create a small flake in the store that
references your flakes, however it also needs to make a second copy of them. If
your configurations live in a large repository, that will be a lot of copying,
and sadly lazy-paths doesn't apply.

There is some filtering going on in nix code (by default it filters out
`_module` access, `assertions`, etc.) that's a bit slow (adds a second or two
on my machine). That probably could be sped up by moving that logic into
python.

Because `evalModules` _needs_ to be replaced to get the tracing data,
configurations nested inside of configurations are a bit tricky, if even
possible. The tracing function checks `_module.args` for a magic attr that
contains calling info, including the path it's nested at. You can see the
`mkNested` function usage in `package.nix` to see how this works for
home-manager in nixos/nix-darwin. I wasn't able to figure out a nice way to get
this to work for nixvim in nixos/home-manager. Maybe its `lib.evalModules`
comes from the flake's nixpkgs input bypassing the traced `lib`? If so, _maybe_
a workaround could be to make a flake that looks like nixpkgs, just with `lib`
replaced and have `nixvim`'s nixpkgs follow that.

<!-- vim:spell
-->
