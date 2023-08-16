let
  pkgs = import <nixpkgs> {};

  ncurses-no-nix-store = pkgs.ncurses.overrideAttrs (finalAttrs: previousAttrs: {
    configureFlags = previousAttrs.configureFlags ++ [ "--with-terminfo-dirs=/usr/share/terminfo" ];
  });
in

pkgs.mkShell {
  buildInputs = [
    pkgs.darwin.apple_sdk.frameworks.AppKit

    pkgs.autoconf
    pkgs.pkgconfig
    ncurses-no-nix-store
    pkgs.zlib

    pkgs.gnutls
    pkgs.jansson
    pkgs.libxml2
    pkgs.librsvg
    pkgs.tree-sitter
    pkgs.sqlite
  ];
}
