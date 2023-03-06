let
  pkgs = import <nixpkgs> {};

  ncurses-no-nix-store = pkgs.ncurses.overrideAttrs (finalAttrs: previousAttrs: {
    configureFlags = previousAttrs.configureFlags ++ [ "--with-terminfo-dirs=/usr/share/terminfo" ];
  });
in

pkgs.mkShell {
  buildInputs = [
    pkgs.darwin.apple_sdk.frameworks.Security
    pkgs.darwin.apple_sdk.frameworks.CoreServices
    pkgs.darwin.apple_sdk.frameworks.CoreFoundation
    pkgs.darwin.apple_sdk.frameworks.Foundation
    pkgs.darwin.apple_sdk.frameworks.AppKit
    pkgs.darwin.apple_sdk.frameworks.WebKit
    pkgs.darwin.apple_sdk.frameworks.Cocoa

    pkgs.autoconf
    pkgs.pkgconfig
    ncurses-no-nix-store
    pkgs.zlib

    pkgs.gnutls
    pkgs.libffi
    pkgs.jansson
    pkgs.libxml2
    pkgs.librsvg
    pkgs.tree-sitter
  ];
}
