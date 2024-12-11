Emacs Build Scripts
===================

These are the emacs build scripts that produces the builds at
http://emacsformacosx.com/.

Prerequisites
-------------

### Hardware Requirements

The scripts are modular and are designed to be run on multiple build
machines (or VMs) and integrate with continuous integration servers (the
builds on emacsformacosx.com run from Jenkins now). This means that you can
build whatever architectures you have access to.

Note that cross-compiling Emacs is (still) not possible due to the "unexec"
step, which requires the binary that was built to be run. So if you want to
build an old architecture (like PowerPC), you need to be running on a system
that can actually execute binaries of that architecture.


### XZ

Recent Emacs pretests are being distributed in `.tar.xz` format. The
"fetch-emacs-from-ftp" script will convert from `.xz` to `.tar.bz2` so that
XZ doesn't need to be installed on every build machine. But you will need
the "xz" program on the machines that runs "fetch-emacs-from-ftp". The
easiest way to get it is through [homebrew](http://brew.sh/): "brew install xz"


### XCode Command Line Tools

Building emacs requires that the XCode command line tools be installed so that
some libraries (libxml2, at least) are available.

    xcode-select --install

Currently, Homebrew installs a pkg-config definition for the built in
libxml2, but uses deprecated paths that don't exist by default on newer
MacOS versions (10.14 at least). The symptom is this error:

      CC       xml.o
    xml.c:26:10: fatal error: 'libxml/tree.h' file not found
    #include <libxml/tree.h>
             ^~~~~~~~~~~~~~~
    1 error generated.

To fix it, run this:

    sudo installer -pkg /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg -target /

### Rust

The launcher is now written in [Rust instead of Ruby](https://emacsformacosx.com/about#rust-launcher).
To build it you need [Rust installed](https://www.rust-lang.org/tools/install).

The Rust `cargo` invocations are wrapped in a `Makefile` that compiles both
`x86_64` and `aarch64` and then uses Apple's `lipo` to combine them into a
fat binary. This requires that you have Rust compiler targets installed for
both `x86_64` and `aarch64` (Apple Silicon). This can be accomplished with
(on an `aarch64` (Apple Silicon) machine):

    rustup target add x86_64-apple-darwin

Or on an x86_64 (Intel) mac:

    rustup target add aarch64-apple-darwin

### Ruby

The system Ruby from macOS 10.12 (ruby 2.3.7p456) should be able to run the
scripts. If you are trying to build on an older macOS, you may need to get a
more recent Ruby installed.

Usage
-----

There are 3 scripts that are designed to be run from some sort of Continuous
Integration software (the builds on http://emacsformacosx.com run from
Jenkins). All three scripts know the `--verbose` command, and are nice and
loud when it is given.

### fetch-emacs-from-ftp

This takes an ftp url (`ftp://ftp.gnu.org/gnu/emacs/`, for example), and
downloads the latest version of the Emacs source code found there. It will
also convert the source from a `.tar.xz` to a `.tar.bz2` (so that the main
build VMs don't need to have "XZ" installed).

### build-emacs-from-tar

This is the main build script. It takes a tar file and a "kind" (`pretest`,
`nightly`, or `release`) as input and unpacks the tar, builds it for a
single architecture, and tars up the resulting Emacs.app file.

You can tell it to build an architecture other than the default with the
`--arch` option (`--arch=powerpc` or `--arch=i386`).

Builds of the main Emacs source repository are expected to be packaged up
into tars elsewhere. http://emacsformacosx.com has a Jenkins job that pulls down
the latest code and then tars it up like so:

    DATE=$(date "+%Y-%m-%d_%H-%M-%S")
    SHORT=$(git rev-parse --short HEAD)
    DIR=emacs-$DATE-$SHORT
    git archive --prefix="$DIR/" HEAD | tar x
    (cd $DIR && ./autogen.sh)
    tar cjf $DIR.tar.bz2 $DIR

#### Emacs Dependencies

By default `build-emacs-from-tar` will attempt to gather several extra
dependencies to make Emacs more full featured. You can disable this with the
`--no-deps` option. There are 2 ways the dependencies can be built:

1. By downloading prebuilt packages using [Nix](https://nixos.org/). If you
   have [installed Nix on your Mac](https://nixos.org/download/#nix-install-macos),
   then `build-emacs-from-tar` should autodetect this and use `nix-shell`
   (which must be in your `PATH`) to install a list of dependencies. The
   dependency list can be found in `dependencies.nix`.

2. By downloading and compiling a list programs. This happens if Nix is not
   installed. The list is canned and can be found in
   `build-dependencies.rb`. This method is not used any more by the builds
   on emacsformacosx.com as it is prone to getting out of date and requires
   a lot of up-keep. The code to do this (`build.rb`) will be removed at
   some point.

No matter which method is used, `build-emacs-from-tar` modifies the
dependencies' libraries as it copies them into `Emacs.app` so that the app
bundle remains portable.

### The Rust launcher

To compile the Rust launcher (needed by `combine-and-package`):

    make

### combine-and-package

This takes multiple tar files as input, unpacks and combines them into a
final "fat" Emacs.app, then creates a final disk image (`.dmg`). It takes an
optional `--sign` parameter (`--sign="my identity"`) which makes it code
sign the Emacs.app.

Example
-------

    $ ./fetch-emacs-from-ftp -v ftp://ftp.gnu.org/pub/gnu/emacs
    + curl --continue-at - --silent -O ftp://ftp.gnu.org/pub/gnu/emacs/emacs-25.1.tar.xz
    shell(#<Th:0x007febed8a48b0>): /usr/local//brew//bin/xzcat emacs-25.1.tar.xz
    shell(#<Th:0x007febed8a48b0>): /usr/bin/bzip2
    $ ls *.bz2
    emacs-25.1.tar.bz2
    $ ./build-emacs-from-tar -v -j 8 emacs-25.1.tar.bz2 release
      ... Lots out output snipped ...
    Built Emacs-25.1-10.12-x86_64.tar.bz2, Emacs-25.1-10.12-x86_64-extra-source.tar
    $ ./combine-and-package -v Emacs-25.1-10.12-x86_64.tar.bz2
      ... More output snipped ...
    created: Emacs-25.1-universal.dmg

License
-------

Copyright © 2004-2021 David Caldwell <david@porkrind.org>

The scripts and programs contained in this distribution are licensed under
the GNU General Public License (v3.0). See the LICENSE file for details.
