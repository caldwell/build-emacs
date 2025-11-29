let
  pkgs = import (builtins.fetchGit {
      name = "emacs-dependencies-base";
      url = "https://github.com/NixOS/nixpkgs/";
      ref = "refs/heads/nixpkgs-unstable";
      rev = "21eda9bc80bef824a037582b1e5a43ba74e92daa";
    }) {};

  ncurses-no-nix-store = pkgs.ncurses.overrideAttrs (finalAttrs: previousAttrs: {
    configureFlags = previousAttrs.configureFlags ++ [ "--with-terminfo-dirs=/usr/share/terminfo" ];
  });
in

pkgs.mkShell {
  buildInputs = [
    pkgs.darwin.apple_sdk.frameworks.AppKit

    pkgs.autoconf
    pkgs.pkg-config or pkgs.pkgconfig
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
