# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
  bundled ? false,
}:
let
  nativeProof = pkgs.pkgsStatic.stdenv.mkDerivation {
    name = "native-static-proof";
    dontUnpack = true;
    buildPhase = ''
      cat > proof.c <<'C'
      #include <stdio.h>
      int main(void) { puts("Hello from native payload"); return 0; }
      C
      $CC proof.c -o proof
    '';
    installPhase = "mkdir -p $out/bin; cp proof $out/bin/";
  };
  tools = import ../nix/tools.nix { inherit pkgs; };
  spell = pkgs.runCommand "native-sorcery-fixture-spell" { } ''
    mkdir -p $out/test/native-marker
    cat > $out/test/native-marker/DETAILS <<'SPELL'
    SPELL=native-marker
    VERSION=1
    SOURCE_DIRECTORY=$BUILD_DIRECTORY/$SPELL-$VERSION
    ENTERED=20261102
    LICENSE[0]=MIT
    SHORT="Native ownership fixture"
    cat << EOT
    Native Sorcery fixture.
    EOT
    SPELL
    echo 'mk_source_dir "$SOURCE_DIRECTORY"' > $out/test/native-marker/PRE_BUILD
    echo ':' > $out/test/native-marker/BUILD
    cat > $out/test/native-marker/INSTALL <<'SPELL'
    mkdir -p /usr/share/sorcery-vm
    echo native > /usr/share/sorcery-vm/marker
    SPELL
    echo ':' > $out/test/native-marker/POST_INSTALL
    echo 'echo final > /var/sorcery-final-marker' > $out/test/native-marker/FINAL
    echo 'echo removed > /var/sorcery-remove-marker' > $out/test/native-marker/POST_REMOVE
    chmod +x $out/test/native-marker/*
    echo 'BUILD_API=2' > $out/API_VERSION
  '';
  tool =
    version:
    pkgs.runCommand "sorcery-tool-${version}"
      {
        pname = "sorcery-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/sorcery-tool
        chmod 755 $out/bin/sorcery-tool
      '';
  app =
    offline: version:
    impurifier.makeSpell {
      pkg = tool version;
      inherit offline;
      users.sorcery-worker = { };
      directories."/var/lib/sorcery-worker" = {
        owner = "sorcery-worker:sorcery-worker";
        mode = "0750";
      };
      configFiles."/etc/sorcery-app.conf" = pkgs.writeText "sorcery-app.conf" "version=${version}\n";
      lifecycle = {
        onInstall = "test -x /opt/nix/profile/bin/sorcery-tool; echo initialized > /var/lib/sorcery-worker/initialized";
        onUpgrade = "test ! -e /var/lib/sorcery-worker/fail; echo ${version} > /var/lib/sorcery-worker/migrated";
      };
    };
  provider =
    name:
    impurifier.buildSpell {
      inherit name;
      version = "1";
      payload =
        pkgs.runCommand "${name}-vm-provider" { }
          "mkdir -p $out/usr/share/impurifier-vm; echo preinstalled > $out/usr/share/impurifier-vm/${name}";
    };
  fixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  driver =
    version:
    impurifier.buildSpell {
      name = "host-driver";
      inherit version;
      payload = fixture.driver version;
    };
  hardware = impurifier.makeOfflineSpell {
    pkg = fixture.tool;
    inherit (fixture) hardware;
    hostDependencies = [ "host-driver" ];
  };
  grimoireWith =
    {
      offline,
      version,
      driverVersion ? "1",
      runtime ? impurifier.runtimeSpell,
    }:
    impurifier.makeGrimoire {
      spells = [
        (provider "nix")
        (provider "python3")
        (provider "castfs")
        runtime
        (app offline version)
        (driver driverVersion)
        hardware
      ];
    };
  nativeGrimoire =
    version:
    impurifier.makeGrimoire {
      spells = [
        (impurifier.makeNativeSpell {
          name = "native-payload";
          inherit version;
          payload = pkgs.runCommand "native-sorcery-${version}" { } ''
            mkdir -p $out/usr/libexec/native-sorcery $out/usr/share
            cp ${nativeProof}/bin/proof $out/usr/libexec/native-sorcery/proof
            echo ${version} > $out/usr/share/native-sorcery-version
          '';
        })
      ];
    };
  grimoire = offline: version: grimoireWith { inherit offline version; };

in
{
  native-vm = pkgs.testers.runNixOSTest {
    name = "sorcery-native-contract";
    requiredFeatures = {
      kvm = false;
      devnet = false;
    };
    nodes.machine = { lib, ... }: {
      virtualisation.memorySize = 2048;
      virtualisation.useNixStoreImage = true;
      virtualisation.writableStore = true;
      nix.settings.substituters = lib.mkForce [ ];
      systemd.tmpfiles.rules = [
        "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
        "L+ /usr/bin/nix-store - - - - ${
          if bundled then
            pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
          else
            "${pkgs.nix}/bin/nix-store"
        }"
        "L+ /usr/bin/nix - - - - ${pkgs.nix}/bin/nix"
      ];
      virtualisation.qemu.package = lib.mkForce pkgs.qemu;
      virtualisation.qemu.forceAccel = false;
      boot.kernelModules = [ "fuse" ];
      environment.systemPackages = [
        tools.castfs
        pkgs.nix
        pkgs.python3
        pkgs.shadow
        pkgs.bash
        pkgs.gawk
        pkgs.gnumake
        pkgs.gnutar
        pkgs.bzip2
        pkgs.gzip
        pkgs.xz
        pkgs.file
        pkgs.procps
        pkgs.which
        pkgs.perl
        pkgs.patch
        pkgs.diffutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.util-linux
        pkgs.gettext
        pkgs.binutils
        pkgs.nettools
        pkgs.dialog
        pkgs.wget
      ];
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      def succeed(command):
          return machine.succeed("export PATH=/usr/sbin:/usr/bin:$PATH; " + command)
      succeed("mkdir -p /usr/bin /usr/sbin /usr/share/archspecs /etc/sorcery/local; for p in /run/current-system/sw/bin/*; do test -e /usr/bin/$(basename $p) || ln -s $p /usr/bin/; done; ln -s ${pkgs.bash}/bin/bash /bin/bash")
      succeed("cp -r ${tools.source} /root/sorcery-source; cd /root/sorcery-source; bash ./install > /tmp/sorcery-install.log 2>&1 || { cat /tmp/sorcery-install.log; exit 1; }")
      succeed("printf 'HOST=x86_64-unknown-linux-gnu\\n' > /usr/share/archspecs/null; printf 'ARCHITECTURE=null\\nPROMPT_DELAY=0\\nVOYEUR=on\\nCOLOR=off\\nSTAGED_INSTALL=on\\nARCHIVE=off\\nGATHER_DOCS=off\\n' >> /etc/sorcery/local/config")
      succeed("cp -r ${spell} /grimoire; echo 'GRIMOIRE_DIR[0]=/grimoire' > /etc/sorcery/local/grimoire")
      succeed("cast --no-opts -c native-marker > /tmp/cast.log 2>&1 || { cat /tmp/cast.log; exit 1; }")
      succeed("grep native /usr/share/sorcery-vm/marker; grep final /var/sorcery-final-marker; grep native-marker /var/state/sorcery/packages; grep /usr/share/sorcery-vm/marker /var/log/sorcery/install/native-marker-1")
      succeed("dispel native-marker > /tmp/dispel.log 2>&1 || { cat /tmp/dispel.log; exit 1; }")
      succeed("test ! -e /usr/share/sorcery-vm/marker; grep removed /var/sorcery-remove-marker")
      def select_grimoire(path):
          succeed(f"rm -rf /grimoire; cp -r {path} /grimoire; chmod -R u+w /grimoire")
      def fail(command):
          return machine.fail("export PATH=/usr/sbin:/usr/bin:$PATH; " + command)
      with subtest("native generated spells without engine activation"):
          for version, path in [(1, "${nativeGrimoire "1"}"), (2, "${nativeGrimoire "2"}")]:
              select_grimoire(path)
              succeed("cast --from /grimoire/source-cache --no-opts -c native-payload > /tmp/native-payload.log 2>&1; grep '^" + str(version) + "$' /usr/share/native-sorcery-version || { cat /tmp/native-payload.log; exit 1; }")
              succeed("grep /usr/libexec/native-sorcery/proof /var/log/sorcery/install/native-payload-" + str(version))
          succeed("mkdir -p /srv/native; cp /usr/libexec/native-sorcery/proof /srv/native/proof; chroot /srv/native /proof | grep Hello; test ! -e /srv/native/nix; test ! -e /usr/sbin/sorcery-impurifier-activate")
          succeed("dispel native-payload; test ! -e /usr/libexec/native-sorcery/proof; test ! -e /usr/share/native-sorcery-version")
      select_grimoire("${grimoire false "1"}")
      succeed("cast --from /grimoire/source-cache --no-opts -c sorcery-impurifier > /tmp/runtime.log 2>&1; test -x /usr/sbin/sorcery-impurifier || { cat /tmp/runtime.log; exit 1; }")
      succeed("test ! -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
      fail("sorcery-impurifier install --from /grimoire/source-cache sorcery-tool > /tmp/net.log 2>&1")
      select_grimoire("${grimoire true "1"}")
      succeed("sorcery-impurifier install --from /grimoire/source-cache sorcery-tool > /tmp/offline.log 2>&1 || { cat /tmp/offline.log; exit 1; }")
      succeed("test $(/opt/nix/profile/bin/sorcery-tool) = 1; id sorcery-worker; test $(stat -c %a /var/lib/sorcery-worker) = 750; grep initialized /var/lib/sorcery-worker/initialized")
      succeed("echo customized > /etc/sorcery-app.conf")
      select_grimoire("${grimoire true "2"}")
      succeed("touch /var/lib/sorcery-worker/fail")
      fail("sorcery-impurifier install --from /grimoire/source-cache sorcery-tool > /tmp/upgrade-fail.log 2>&1")
      succeed("rm /var/lib/sorcery-worker/fail; sorcery-impurifier reconcile; test $(/opt/nix/profile/bin/sorcery-tool) = 2; grep 2 /var/lib/sorcery-worker/migrated")
      succeed("grep customized /etc/sorcery-app.conf; ! grep '^/nix/store/' /var/log/sorcery/install/sorcery-tool-2-offline")
      succeed("sorcery-impurifier install --from /grimoire/source-cache hardware-tool > /tmp/hardware.log 2>&1 || { cat /tmp/hardware.log; exit 1; }")
      succeed("test $(/opt/nix/profile/bin/hardware-tool) = 1; grep 'host-driver:.*:installed:' /var/state/sorcery/packages")
      select_grimoire("${
        grimoireWith {
          offline = true;
          version = "2";
          driverVersion = "2";
        }
      }")
      succeed("cast --from /grimoire/source-cache --no-opts -c host-driver > /tmp/driver-native.log 2>&1; test $(/opt/nix/profile/bin/hardware-tool) = 2")
      select_grimoire("${
        grimoireWith {
          offline = true;
          version = "2";
          driverVersion = "2";
          runtime = impurifier.makeRuntimeSpell { version = "0.1"; };
        }
      }")
      fail("sorcery-impurifier install --from /grimoire/source-cache sorcery-impurifier > /tmp/legacy-runtime.log 2>&1")
      succeed("test $(/opt/nix/profile/bin/sorcery-tool) = 2")
      select_grimoire("${
        grimoireWith {
          offline = true;
          version = "2";
          driverVersion = "2";
        }
      }")
      succeed("sorcery-impurifier install --from /grimoire/source-cache sorcery-impurifier > /tmp/current-runtime.log 2>&1 || { cat /tmp/current-runtime.log; exit 1; }")
      succeed("for file in /grimoire/impurifiers/sorcery-tool/*.tar.gz; do mv \"$file\" \"$file.hidden\"; done; rm -f /var/spool/sorcery/sorcery-tool-*.tar.gz")
      fail("sorcery-impurifier install --from /grimoire/source-cache sorcery-tool > /tmp/dropped.log 2>&1")
      succeed("grep 'native cast did not complete' /tmp/dropped.log; test $(/opt/nix/profile/bin/sorcery-tool) = 2")
      succeed("for file in /grimoire/impurifiers/sorcery-tool/*.hidden; do mv \"$file\" \"''${file%.hidden}\"; done")
      succeed("nix-collect-garbage; test $(/opt/nix/profile/bin/sorcery-tool) = 2")
      succeed("test $(/opt/nix/profile/bin/hardware-tool) = 2")
      succeed("sorcery-impurifier remove hardware-tool; sorcery-impurifier remove host-driver")
      fail("/usr/sbin/sorcery-impurifier-activate remove /foreign / /")
      fail("INSTALL_ROOT=/foreign sorcery-impurifier reconcile")
      succeed("sorcery-impurifier remove sorcery-tool > /tmp/remove-app.log 2>&1 || { cat /tmp/remove-app.log; exit 1; }")
      succeed("test ! -e /opt/nix/profile/bin/sorcery-tool; test -f /var/lib/sorcery-worker/initialized; grep customized /etc/sorcery-app.conf")
    '';
  };
}
