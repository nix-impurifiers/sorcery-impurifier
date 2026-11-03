# sorcery-impurifier

Build native Sorcery spells and grimoires backed by transactional Nix profiles.
Sorcery's actual `cast`, dependency resolver, CastFS and `dispel` own host files;
Nix owns application closures and garbage-collection roots. Original code is MIT.
See THIRD_PARTY.md for native tools and compatibility patches.

```nix
let
  sorcery = inputs.sorcery-impurifier.lib.sorcery-impurifier { inherit pkgs; };
in sorcery.makeGrimoire {
  spells = [
    (sorcery.makeRuntimeSpell {
      nixDependency = "my-nix-provider";
      pythonDependency = "python3";
    })
    (sorcery.makeOfflineSpell { pkg = pkgs.hello; })
  ];
}
```

Register the generated directory as a local grimoire through your normal Sorcery
configuration. It contains an `impurifiers` section and a bundled `source-cache`.
Supply providers for the runtime's native Nix/Python/CastFS dependencies in your usual
grimoires. With Nix and Python already installed, bootstrap the runtime natively:

```
cast --from /srv/impurifiers/source-cache -c sorcery-impurifier
sorcery-impurifier install --from /srv/impurifiers/source-cache hello
sorcery-impurifier reconcile
sorcery-impurifier remove hello
```

The adapter uses native `--from` rather than replacing Sorcery's downloader or
checksum checks. The pinned upstream `file://` downloader returns failure even
after copying a file; supplying the bundled source cache avoids that path. You
may instead copy its archives into your configured native source cache. Each
archive has a native SHA-512 checksum and a unique source filename. Copy the
whole grimoire to another machine; the recipe does not require a build-machine
store path for its source archive.

`makeNetSpell` emits a small installable reference that needs its Nix closure to
be available. `makeOfflineSpell` embeds a NAR cache. Both use the same logical
native spell name, with a `-net` or `-offline` native version suffix. One flavor
may be selected in a grimoire at a time. `makeGrimoire` rejects duplicate names.
`buildSpell` also accepts arbitrary native payloads and exact-name dependencies,
which can express a future impure Nix provider package. Nix provisioning and a
new installer remain deferred work.

The runtime also installs native `cast_final` and `post_dispel` hooks, so ordinary
native host-library updates trigger reconciliation. Upgrade-time removal checks
for a live native `cast` ancestor, including its `casting_safe` copy, before
deferring cleanup until replacement installation.

The generated spell requires native CastFS staging; it fails before installation
if Sorcery falls back to an unverified tracking path. The runtime defaults to a
`castfs` dependency; `castfsDependency` selects another native provider name.

With native `PRESERVE=on`, the VM verifies that edited configuration survives
upgrade and removal. Native Sorcery owns that policy; the adapter does not
overwrite the administrator's choice.

The generated spell uses API 2, native source unpacking and checksum validation,
a native tracked installation, `FINAL` activation and `POST_REMOVE` cleanup.
Accounts, directory permissions, lifecycle hooks and host-library snapshots use
the shared engine. Service declarations are rejected until native service policy
is implemented; this backend does not assume systemd, OpenRC or runit.

Native commands do not guarantee activation success. In particular, `cast` can
return zero after dropping spells during download, and native hook pipelines can
hide hook failure. The adapter checks fresh native cast success records, verifies
removal state, and reconciles after the native operation. Repair a failed
activation's cause and run `reconcile`; native package repair still uses Sorcery.
Foreign install, state or tracking roots are rejected before adapter mutations;
spell callbacks independently guard activation against foreign roots.

Run `nix flake check -L` for the QEMU native transaction suite and `nix fmt` for
formatting. Tests run upstream Sorcery scripts with actual CastFS/Linux FUSE on a
full-install filesystem. They do not establish Source Mage boot/init integration,
all architecture profiles or historical installwatch compatibility.

## Native payloads and bundled clients

`makeNativeSpell { name; version; payload; dependencies?; ... }` emits a native
recipe from a producer-prepared tree, with engine activation disabled and no
implicit Nix dependency. Ordinary cast/dispel owns installation and removal using
real CastFS. The producer prepares a runnable target layout; this does not
relocate binaries. The VM installs two generated native versions before the
engine, checks native inventories and removal, and executes the installed static
payload in an isolated root without `/nix`. The manager fixture itself uses
NixOS host tools; this does not claim a complete target-distro boot without Nix.

`makeRuntimeSpell` optionally accepts `bundledNixStore` and
`bundledNixNotices` for a static ELF client and upstream notices. Bundling omits
the default Nix dependency; Python and the native file tracker remain required.
Compatible external clients take precedence, explicit `IMPURIFIER_NIX_STORE`
disables fallback, and failed mutations are never retried through another
client. A bundled variant repeats the original lifecycle suite with an
incompatible external candidate. Nix provisioning remains deferred.
