{
  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;

  outputs = { self, nixpkgs }:
  with nixpkgs.lib;
  let
    systems = platforms.unix;
    forAllSystems = fn: (genAttrs systems (system:
      fn (import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
        ];
      })
    ));
    getHaskellPackages = pkgs: pattern: pipe pkgs.haskell.packages [
      attrNames
      (filter (x: !isNull (strings.match pattern x)))
      (sort (x: y: x>y))
      (map (x: pkgs.haskell.packages.${x}))
      head
    ];
  in {
    packages = forAllSystems (pkgs: let
      ghc92 = getHaskellPackages pkgs "ghc92.";
    in rec {
      default = senseair-s8;
      senseair-s8 = ghc92.senseair-s8;
    });

    overlays = {
      default = final: prev: {
        haskell = prev.haskell // {
          packageOverrides = hfinal: hprev: prev.haskell.packageOverrides hfinal hprev // {
            senseair-s8 = hfinal.callCabal2nix "senseair-s8" ./senseair-s8 {};

            # https://gitlab.haskell.org/ghc/ghc/-/issues/22425
            ListLike = final.haskell.lib.dontCheck hprev.ListLike;
          };
        };
      };
    };

    devShells = forAllSystems (pkgs:
      let
        haskellPackages = getHaskellPackages pkgs "ghc92.";
      in rec {
        default = haskellPackages.shellFor {
          packages = hpkgs: [
            hpkgs.senseair-s8
          ];
          nativeBuildInputs = [
            haskellPackages.haskell-language-server
            pkgs.cabal-install
            pkgs.hlint

            # in addition, for ghcid-wrapper
            pkgs.zsh
            pkgs.entr
            pkgs.ghcid
          ];
        };
      }
    );
  };
}
