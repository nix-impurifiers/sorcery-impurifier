# Third-party material

Original recipes, adapters and test definitions in this repository are MIT.
Tests fetch the actual Source Mage Sorcery scripts at
`39a44962cbe9dfbbb1b24461595ee025a8cbd30f` from
https://github.com/sourcemage/sorcery. Their upstream GPL 2-or-later notices
remain intact; the fixture runs the native installer and preserves COPYING.

CastFS is fetched from https://github.com/sourcemage/castfs at
`0325298f22ed405280a05a119f5f78834a85633f`. Its GPL notices and COPYING remain
intact. The build uses `-fcommon` for its historical shared global declarations
and supplies mode `0600` to its existing `open(..., O_CREAT)` call. The latter
fix makes file creation defined and permits current fortified libc builds;
the existing copy operation subsequently applies source ownership and mode.
See nix/tools.nix for the complete reproducible source change.
