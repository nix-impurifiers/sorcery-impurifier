# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "sorcery-impurifier";
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
  };
  valid = name: builtins.match "[a-z0-9][a-z0-9+._-]*" name != null;
  buildSpell =
    {
      name,
      version,
      payload,
      dependencies ? [ ],
      activate ? false,
      licenses ? [ "MIT" ],
      description ? "Nix projected application",
    }:
    assert lib.assertMsg (
      valid name && valid version && lib.all valid dependencies
    ) "invalid spell identity or dependency";
    let
      archive = "${name}-${version}-${builtins.substring 0 32 (builtins.baseNameOf payload)}.tar.gz";
      details = pkgs.writeText "spell-details" ''
        SPELL=${lib.escapeShellArg name}
        VERSION=${lib.escapeShellArg version}
        SOURCE=${lib.escapeShellArg archive}
        SOURCE_URL[0]="file://$SCRIPT_DIRECTORY/$SOURCE"
        SOURCE_DIRECTORY="$BUILD_DIRECTORY/$SPELL-$VERSION"
        SOURCE_HASH=sha512:PAYLOAD_HASH
        ENTERED=20261102
        BUILD_API=2
        ${lib.concatStringsSep "\n" (
          lib.imap0 (i: license: "LICENSE[${toString i}]=${lib.escapeShellArg license}") licenses
        )}
        SHORT=${lib.escapeShellArg description}
        printf '%s\n' ${lib.escapeShellArg description}
      '';
      phase =
        mode:
        pkgs.writeText "spell-phase-${mode}" ''
          # SPDX-License-Identifier: MIT
          if [[ -x /usr/sbin/sorcery-impurifier-activate ]]; then
            /usr/sbin/sorcery-impurifier-activate ${mode} "''${INSTALL_ROOT:-/}" "''${STATE_ROOT:-/}" "''${TRACK_ROOT:-/}"
          fi
        '';
    in
    pkgs.runCommand "${name}-${version}-spell"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru = { inherit name version; };
      }
      ''
        mkdir -p root/${name}-${version}/root $out/${name}
        cp ${../LICENSE} $out/${name}/LICENSE
        cp -r ${payload}/. root/${name}-${version}/root/
        chmod -R u+w root
        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -C root -cf - ${name}-${version} | gzip -n > $out/${name}/${archive}
        hash=$(sha512sum $out/${name}/${archive} | cut -d' ' -f1)
        sed "s/PAYLOAD_HASH/$hash/" ${details} > $out/${name}/DETAILS
        cat > $out/${name}/PRE_BUILD <<'PRE_BUILD'
        [[ $STAGED_INSTALL == on ]] || { message 'Impurifier spells require native CastFS staging'; return 1; }
        default_pre_build
        PRE_BUILD
        printf ':\n' > $out/${name}/BUILD
        cat > $out/${name}/INSTALL <<'INSTALL'
        cp -a "$SOURCE_DIRECTORY/root/." "''${INSTALL_ROOT:-/}/"
        INSTALL
        printf ':\n' > $out/${name}/POST_INSTALL
        ${lib.optionalString activate ''
          cp ${phase "activate"} $out/${name}/FINAL
          cp ${phase "remove"} $out/${name}/POST_REMOVE
        ''}
        ${lib.optionalString (dependencies != [ ]) ''
          printf '%s\n' ${
            lib.concatMapStringsSep " " (d: lib.escapeShellArg "depends ${d}") dependencies
          } > $out/${name}/DEPENDS
        ''}
        chmod 755 $out/${name}/{DETAILS,PRE_BUILD,BUILD,INSTALL,POST_INSTALL}
        find $out/${name} -maxdepth 1 -type f ! -name '*.tar.gz' -exec chmod 755 {} +
      '';
  makeRuntimeSpell =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
      castfsDependency ? "castfs",
      version ? core.runtimeVersion,
    }:
    buildSpell {
      name = "sorcery-impurifier";
      inherit version;
      dependencies = [
        nixDependency
        pythonDependency
        castfsDependency
      ];
      activate = true;
      payload = pkgs.runCommand "sorcery-runtime" { } ''
        cp -r ${core.makeRuntimeTree { }} $out
        chmod -R u+w $out
        install -Dm755 ${../src/activate.py} $out/usr/sbin/sorcery-impurifier-activate
        install -Dm755 ${../src/nix_impurifier.hook} $out/etc/sorcery/hooks/nix_impurifier.hook
        install -Dm755 ${../src/adapter.py} $out/usr/sbin/sorcery-impurifier
        mkdir -p $out/usr/share/sorcery-impurifier
        echo '${version}' > $out/usr/share/sorcery-impurifier/runtime-version
      '';
    };
  makeSpell =
    args@{
      pkg,
      hostDependencies ? [ ],
      ...
    }:
    assert lib.assertMsg (
      (args.systemd or null) == null && (args.openrc or null) == null && (args.runit or null) == null
    ) "Sorcery service startup remains native host policy; no systemd/OpenRC/runit backend is assumed";
    let
      application = core.makePayload (
        (builtins.removeAttrs args [ "hostDependencies" ]) // { hostBackend = "openrc"; }
      );
      payload = pkgs.runCommand "sorcery-application" { } ''
        cp -r ${application} $out
        chmod -R u+w $out
        mkdir -p $out/usr/share/sorcery-impurifier/requirements
        echo '${core.runtimeVersion}' > $out/usr/share/sorcery-impurifier/requirements/${application.name}
      '';
    in
    buildSpell {
      name = application.name;
      version = "${application.version}-${if application.offline then "offline" else "net"}";
      inherit payload;
      inherit (application) description;
      licenses = [
        "MIT"
      ]
      ++ map (license: if builtins.isAttrs license then license.spdxId or "UNKNOWN" else "UNKNOWN") (
        lib.toList (pkg.meta.license or [ ])
      );
      dependencies = [ "sorcery-impurifier" ] ++ hostDependencies;
      activate = true;
    };
  makeGrimoire =
    {
      spells,
      name ? "impurifiers",
    }:
    assert lib.assertMsg (
      lib.length (lib.unique (map (s: s.name) spells)) == lib.length spells
    ) "one selected spell per logical package";
    pkgs.runCommand "${name}-grimoire"
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir -p $out/impurifiers $out/source-cache
        cp ${../LICENSE} $out/LICENSE
        ${lib.concatMapStringsSep "\n" (s: "cp -r ${s}/. $out/impurifiers/") spells}
        for archive in $out/impurifiers/*/*.tar.gz; do
          ln -s "../''${archive#"$out/"}" "$out/source-cache/''${archive##*/}"
        done
        echo 'BUILD_API=2' > $out/API_VERSION
        chmod 755 $out/API_VERSION
      '';
in
{
  inherit
    buildSpell
    makeSpell
    makeRuntimeSpell
    makeGrimoire
    ;
  makeNetSpell = args: makeSpell (args // { offline = false; });
  makeOfflineSpell = args: makeSpell (args // { offline = true; });
  makePackage = args: {
    net = makeSpell (args // { offline = false; });
    offline = makeSpell (args // { offline = true; });
  };
  runtimeSpell = makeRuntimeSpell { };
  inherit (core) unit;
}
