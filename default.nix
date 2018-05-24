{ compiler ? "ghc822"

, doProfiling ? false
, doBenchmark ? false
, doTracing   ? false
, doStrict    ? false

, rev     ? "9d0b6b9dfc92a2704e2111aa836f5bdbf8c9ba42"
, sha256  ? "096r7ylnwz4nshrfkh127dg8nhrcvgpr69l4xrdgy3kbq049r3nb"
, nixpkgs ?
    if builtins.compareVersions builtins.nixVersion "2.0" < 0
    then abort "hnix requires at least nix 2.0"
    else import (builtins.fetchTarball {
           url = "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz";
           inherit sha256; }) {
           config.allowUnfree = true;
           config.allowBroken = false;
         }
, provideDrv  ? !nixpkgs.pkgs.lib.inNixShell
}:

let inherit (nixpkgs) pkgs;

  haskellPackages' = pkgs.haskell.packages.${compiler};

  haskellPackages = pkgs.lib.fix (this: haskellPackages'.override {
    overrides = with pkgs.haskell.lib; self: super: {
      developPackage =
        { root
        , source-overrides ? {}
        , overrides ? self: super: {}
        , modifier ? drv: drv
        , provideDrv ? !pkgs.lib.inNixShell }:
        let drv =
          (this.extend
             (pkgs.lib.composeExtensions
                (self.packageSourceOverrides source-overrides)
                overrides))
          .callCabal2nix (builtins.baseNameOf root) root {};
        in if provideDrv then modifier drv else (modifier drv).env;
    }

    // (if compiler == "ghcjs" then {} else
    {
      cryptohash-md5    = doJailbreak super.cryptohash-md5;
      cryptohash-sha1   = doJailbreak super.cryptohash-sha1;
      cryptohash-sha256 = doJailbreak super.cryptohash-sha256;
      cryptohash-sha512 = doJailbreak super.cryptohash-sha512;
      serialise         = dontCheck super.serialise;

      ghc-datasize =
        if doProfiling
        then null
        else overrideCabal super.ghc-datasize (attrs: {
               enableLibraryProfiling    = false;
               enableExecutableProfiling = false;
             });

      ghc-heap-view =
        if doProfiling
        then null
        else overrideCabal super.ghc-heap-view (attrs: {
               enableLibraryProfiling    = false;
               enableExecutableProfiling = false;
             });
    });
  });

in haskellPackages.developPackage {
  root = ./.;

  overrides = with pkgs.haskell.lib; self: super:
    if compiler == "ghc802"
    then {
      concurrent-output = doJailbreak super.concurrent-output;
    }
    else {};

  source-overrides =
    if compiler == "ghc802"
    then {
      lens-family-core = "1.2.1";
      lens-family = "1.2.1";
    }
    else {};

  modifier = drv: pkgs.haskell.lib.overrideCabal drv (attrs: {
    testHaskellDepends = attrs.testHaskellDepends ++
      [ pkgs.nix

        # Use the same version of hpack no matter what the compiler version
        # is, so that we know exactly what the contents of the generated
        # .cabal file will be. Otherwise, Travis may error out claiming that
        # the cabal file needs to be updated because the result is different
        # that the version we committed to Git.
        pkgs.haskell.packages.ghc822.hpack

        (let cabalInstallVersion = {
               ghc802 = "1.24.0.2";
               ghc822 = "2.0.0.1";
               ghc842 = "2.2.0.0";
             }; in
         haskellPackages.callHackage "cabal-install"
          cabalInstallVersion.${compiler} {})
      ];

    enableLibraryProfiling    = doProfiling;
    enableExecutableProfiling = doProfiling;

    inherit doBenchmark;

    configureFlags =
         pkgs.stdenv.lib.optional doTracing   "--flags=tracing"
      ++ pkgs.stdenv.lib.optional doProfiling "--flags=profiling"
      ++ pkgs.stdenv.lib.optional doStrict    "--ghc-options=-Werror";
  });

  inherit provideDrv;
}
