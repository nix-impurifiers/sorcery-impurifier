# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }: {
  flake.lib = lib.mkForce {
    sorcery-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
        sourceInfo = inputs.self;
      };
    in
    {
      formatter = pkgs.nixfmt-tree;
      packages = {
        castfs = (import ../../../nix/tools.nix { inherit pkgs; }).castfs;
        default = impurifier.runtimeSpell;
      };
      checks =
        (import ../../../tests {
          inherit pkgs impurifier;
          coreSrc = inputs.impurifier;
        })
        // {
          bundled-vm =
            (import ../../../tests {
              inherit pkgs;
              coreSrc = inputs.impurifier;
              bundled = true;
              impurifier =
                let
                  wrap =
                    args:
                    impurifier.makeRuntimeSpell (
                      args
                      // {
                        bundledNixStore = "${
                          import (inputs.impurifier + "/tests/static-nix.nix") { inherit pkgs; }
                        }/bin/nix-store";
                        bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
                      }
                    );
                in
                impurifier
                // {
                  makeRuntimeSpell = wrap;
                  runtimeSpell = wrap { };
                };
            }).native-vm;
        };
    };
}
