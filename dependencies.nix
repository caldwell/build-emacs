let
  system = {
    x86_64-darwin = {
      pkgs = nixpkgs_at_rev "21eda9bc80bef824a037582b1e5a43ba74e92daa";
    };

    aarch64-darwin = {
      pkgs = nixpkgs_at_rev "a8d610af3f1a5fb71e23e08434d8d61a466fc942";
    };
  }.${builtins.currentSystem} or (throw "Unknown macOS system ${builtins.currentSystem}");

  inherit (system) pkgs;

  nixpkgs_at_rev = rev: import (builtins.fetchGit {
    name = "emacs-dependencies-base";
    url = "https://github.com/NixOS/nixpkgs/";
    ref = "refs/heads/nixpkgs-unstable";
    inherit rev;
  }) {};

  ncurses-no-nix-store = pkgs.ncurses.overrideAttrs (finalAttrs: previousAttrs: {
    configureFlags = previousAttrs.configureFlags ++ [ "--with-terminfo-dirs=/usr/share/terminfo" ];
  });
in

pkgs.mkShell {
  buildInputs = [
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
  ] ++ (
    # This magic checks for the existence of darwin.apple_sdk.frameworks.AppKit which is only available in the
    # old nixpkgs we need to use for intel macs. In the newer nixpkgs, this isn't just nonexistent, it actively
    # throws, hence the weird tryEval stuff.
    if let e = { x = pkgs?darwin.apple_sdk.frameworks.AppKit; }; in (builtins.tryEval (builtins.deepSeq e e)).value?x
    then [pkgs.darwin.apple_sdk.frameworks.AppKit]
    else []
  );
}
