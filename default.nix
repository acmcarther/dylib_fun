# TODO: Untangle this crazy business
with (import <nixpkgs> {});
let
  pkgs = import <nixpkgs> {};
in pkgs.stdenv.mkDerivation rec {
  name = "dylib_fun";
  buildInputs = [ pkgs.cmake ];
}
