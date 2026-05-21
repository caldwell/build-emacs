let
  inherit (builtins) compareVersions elemAt readFile splitVersion;
  macos_full_version = readFile (
    (import <nixpkgs> {}).runCommandLocal "macos-version" {} ''
      echo -n $(/usr/bin/sw_vers -productVersion) > $out
    ''
  );

  macos_major_version =
    let v = splitVersion macos_full_version;
    in if (compareVersions macos_full_version "11.0") < 0
       then (elemAt v 0) + "_" + (elemAt v 0)
       else (elemAt v 0);

  system = {
    x86_64-darwin = if (compareVersions macos_major_version "10.14") <= 0 then {
      pkgs = nixpkgs_at_rev "882842d2a908700540d206baa79efb922ac1c33d";
      tree-sitter = tree-sitter-backport;
    } else if (compareVersions macos_major_version "11") <= 0 then {
      pkgs = nixpkgs_at_rev "11cb3517b3af6af300dd6c055aeda73c9bf52c48"; # 25.05
      tree-sitter = tree-sitter-backport;
    } else throw "Haven't figured out what runs on macOS ${macos_major_version} (x86_64)";

    aarch64-darwin = {
      pkgs = nixpkgs_at_rev "a8d610af3f1a5fb71e23e08434d8d61a466fc942";
      tree-sitter = pkgs.tree-sitter;
    };
  }.${builtins.currentSystem} or (throw "Unknown macOS system ${builtins.currentSystem}");

  inherit (system) pkgs tree-sitter;

  nixpkgs_at_rev = rev: import (builtins.fetchGit {
    name = "emacs-dependencies-base";
    url = "https://github.com/NixOS/nixpkgs/";
    ref = "refs/heads/nixpkgs-unstable";
    inherit rev;
  }) {};

  tree-sitter-backport = pkgs.tree-sitter.overrideAttrs (finalAttrs: previousAttrs: {
    __intentionallyOverridingVersion = true;
    version = "0.25.10";
    hash = "sha256-aHszbvLCLqCwAS4F4UmM3wbSb81QuG9FM7BDHTu1ZvM=";
    cargoHash = "sha256-/gYOehFW190STjkIDDH3vJjG45sBww6E+1Rz09aM9Cs=";

    # This will only work with older nixpkgs. In e33a761efdec0ff79cf5ae2d309c95c62fc72c12 (2024-12-08) they switched to using a patch file.
    postPatch = ''
      # remove web interface
      sed -e '/pub mod playground/d' \
          -i cli/src/lib.rs
      sed -e 's/playground,//' \
          -e 's/playground::serve(&\?grammar_path.*$/println!("ERROR: web-ui is not available in this nixpkgs build; enable the webUISupport"); std::process::exit(1);/' \
          -i cli/src/main.rs
    '';
  });

  ncurses-no-nix-store = pkgs.ncurses.overrideAttrs (finalAttrs: previousAttrs: {
    configureFlags = previousAttrs.configureFlags ++ [ "--with-terminfo-dirs=/usr/share/terminfo" ];
  });

  deps = [
    pkgs.gnutls
    pkgs.jansson
    pkgs.libxml2
    pkgs.librsvg
    tree-sitter
    pkgs.sqlite
  ] ++ (
    if compareVersions macos_major_version "11" >= 0
    then [ pkgs.libgccjit ]
    else []
  );

  dependency-details = (map (dep: {
    name = dep.pname;
    version = dep.version;
    path = "${dep}";
    nix_source = "${dep.src}";
  }) deps);
in

pkgs.mkShell {
  passthru = {
    inherit pkgs deps dependency-details ncurses-no-nix-store tree-sitter-backport system macos_full_version macos_major_version;
  };

  buildInputs = [
    pkgs.autoconf
    pkgs.pkg-config or pkgs.pkgconfig
    ncurses-no-nix-store
    pkgs.zlib
  ] ++ deps
  ++ (
    # This magics check for the existence of darwin.apple_sdk.frameworks.AppKit which is only available in the
    # old nixpkgs we need to use for intel macs. In the newer nixpkgs, this isn't just nonexistent, it actively
    # throws, hence the weird tryEval stuff.
    if let e = { x = pkgs?darwin.apple_sdk.frameworks.AppKit; }; in (builtins.tryEval (builtins.deepSeq e e)).value?x
    then [pkgs.darwin.apple_sdk.frameworks.AppKit]
    else []
  );

  # Publish some Nix details that build-emacs-from-tar can use
  DEPENDENCY_DETAILS = builtins.toJSON dependency-details;
}
