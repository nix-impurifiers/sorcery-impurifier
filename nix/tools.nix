# SPDX-License-Identifier: MIT
{ pkgs }:
{
  source = pkgs.fetchFromGitHub {
    owner = "sourcemage";
    repo = "sorcery";
    rev = "39a44962cbe9dfbbb1b24461595ee025a8cbd30f";
    hash = "sha256-rFvfq5aqb9jwB3TmYqmhcWFLcwWiSZ99IMNW8Yfu9r4=";
  };
  castfs = pkgs.stdenv.mkDerivation {
    pname = "castfs";
    version = "2015-03-27";
    src = pkgs.fetchFromGitHub {
      owner = "sourcemage";
      repo = "castfs";
      rev = "0325298f22ed405280a05a119f5f78834a85633f";
      hash = "sha256-mXRG7aOp7r8JPP1PqI0O7i5GLcFzEF9CIpiD13d6Lw4=";
    };
    env.NIX_CFLAGS_COMPILE = "-fcommon";
    nativeBuildInputs = [
      pkgs.autoreconfHook
      pkgs.pkg-config
    ];
    buildInputs = [ pkgs.fuse ];
    postPatch = ''
      substituteInPlace src/utils.c --replace-fail 'open(to, O_WRONLY | O_TRUNC | O_CREAT)' 'open(to, O_WRONLY | O_TRUNC | O_CREAT, 0600)'
    '';
    configureFlags = [ "--disable-documentation" ];
    postInstall = "install -Dm644 COPYING $out/share/licenses/castfs/COPYING";
    meta.license = pkgs.lib.licenses.gpl2Plus;
  };
}
