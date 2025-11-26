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

  deps = [
    pkgs.gnutls
    pkgs.jansson
    pkgs.libxml2
    pkgs.librsvg
    pkgs.tree-sitter
    pkgs.sqlite
  ];

  dependency-details = (map (dep: {
    name = dep.pname;
    version = dep.version;
    path = "${dep}";
    nix_source = "${dep.src}";
    source =
      let archive-name = builtins.baseNameOf dep.src.resolvedUrl or dep.src.url;
      in if (pkgs.lib.hasSuffix archive-name dep.src.outPath)
         then archive-name
         else "${dep.name}.tar.bz2";
  }) deps);

  dependencies.tar = pkgs.stdenv.mkDerivation rec {
    name = "dependencies.tar";
    buildInputs = [ pkgs.ruby ];
    dontUnpack = true;
    manifest = builtins.toJSON (map (deets: builtins.removeAttrs deets ["path"]) dependency-details);
    buildPhase = ''
      (set -x
      mkdir dependencies
      ruby -r json -r fileutils <<EOF
        manifest=JSON.load(ENV['manifest'])
        manifest.each do |dep|
          if File.directory? dep['nix_source']
            system(*%W"tar cjf dependencies/#{dep['name']}-#{dep['version']}.tar.bz2 -C #{dep['nix_source']} --transform s/\./#{dep['name']}-#{dep['version']}/ .")
          else
            FileUtils.cp dep['nix_source'], "dependencies/#{dep['source']}"
          end
        end
        File.write("dependencies/manifest.json", manifest.to_json)
      EOF
      )
    '';
    installPhase = ''
      tar cf "$out" dependencies
    '';
  };
in

pkgs.mkShell {
  passthru = {
    inherit pkgs deps dependency-details dependencies ncurses-no-nix-store system;
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
  DEPENDENCIES_TAR = "${dependencies.tar}";
}
