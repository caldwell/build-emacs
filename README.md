Emacs Build Scripts
===================

These are the Emacs build scripts that produce the builds at
https://emacsformacos.com/.

Project Status and Scope
------------------------

The scripts here are focused on building Emacs for [Emacs For
macOS](https://emacsformacos.com/). They aren't trying to be overly generic
with a ton of options for every conceivable situation. However, they are
abstracted enough to be coerced into different
[CI](https://en.wikipedia.org/wiki/Continuous_integration) systems. So
perhaps they will be useful to someone else (even if for no other reason
than seeing how the sausage gets made).

There is no guarantee of "API"/"UI" stability—command line options and
defaults might change.

This GitHub repo is a mirror of the main repo that the builds are actually
built from. That repo is private as there is a lot of churn while developing
(it gets force pushed _a lot_ while end-to-end testing the CI). I try to
push to this public repo when the code has stabilized (ie, the force pushing
has stopped) but sometimes I forget.

This repo might go for long periods of time without updates. However, as
long as I continue to be an Emacs and macOS user, I will to continue to run
[Emacs For macOS](https://emacsformacos.com/) and keep tweaking the builds
as makes sense.

Prerequisites
-------------

### Hardware Requirements

The scripts are modular and are designed to be run on multiple build
machines (or VMs) and integrate with continuous integration servers (the
builds on emacsformacosx.com run from Jenkins now). This means that you can
build whatever architectures you have access to.

Historically cross-compiling Emacs wasn't possible due to the "unexec" step,
which required the binary that was built to be run. Modern Emacs uses a
"portable" dumper now, so cross-compilation may be possible. These scripts
do not attempt cross-compilation (aside from the launcher) because they were
written before the portable dumper existed and changing it hasn't been worth
the effort yet.

### XCode Command Line Tools

Building Emacs requires that the XCode command line tools be installed so that
some libraries (libxml2, at least) are available.

    xcode-select --install

Currently, Homebrew installs a pkg-config definition for the built in
libxml2, but uses deprecated paths that don't exist by default on newer
macOS versions (10.14 at least). The symptom is this error:

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
downloads the latest version of the Emacs source code found there (preferring
`.tar.xz` archives). 

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
    tar cJf $DIR.tar.xz $DIR

#### Emacs Dependencies (automatic)

By default `build-emacs-from-tar` will attempt to gather several extra
dependencies to make Emacs more full featured. You can disable this with the
`--no-deps` option. There are 2 ways the script can automatically manage
dependencies:

1. By downloading prebuilt packages using [Nix](https://nixos.org/). If you
   have [installed Nix on your Mac](https://nixos.org/download/#nix-install-macos),
   then `build-emacs-from-tar` should auto-detect this and use `nix-shell`
   (which must be in your `PATH`) to install a list of dependencies. The
   dependency list can be found in `dependencies.nix`.

2. By downloading and compiling a list programs. This happens if Nix is not
   installed. The list is canned and can be found in
   `build-dependencies.rb`. This method is considered deprecated and is only
   used by emacsformacosx.com for building on Mac OS X 10.12 since Nix
   doesn't support that version. This method is prone to getting out of date
   and requires lot of up-keep. The code to do this (`build.rb`) will be
   removed once we stop building on 10.12.

No matter which method is used, `build-emacs-from-tar` modifies the
dependencies' libraries as it copies them into `Emacs.app` so that the app
bundle remains portable.

> [!IMPORTANT]
> You almost certainly don't want to use method 2 on a modern macOS. If you
> don't have Nix installed, you'll have to manually install any dependencies
> (using `--no-deps`, see below).

#### Emacs Dependencies (manual)

You can manage the dependencies yourself using the `--no-deps` option. As long
as they are in the `PATH` (and the `PKG_CONFIG_PATH`) then Emacs's
`configure` script should find them and use them.

> [!NOTE]
> There is no provision for making a portable app bundle with `--no-deps`.

### The Rust launcher

To compile the Rust launcher (needed by `combine-and-package`):

    make

### combine-and-package

This takes multiple tar files as input, unpacks and combines them into a
final "fat" Emacs.app, then creates a final disk image (`.dmg`).

#### Notable parameters:

* `--sign=<identity>` (optional)

  If this is passed in then it code signs the Emacs.app.

* `--keychain-profile=<name>` (optional)

  If this is passed in then it will notarize the final `.dmg`. This uses a
  keychain profile so that you don't have to trust your Apple ID and
  password to the script. You can use Apple's tools to set up a keychain
  profile:

  ```
  xcrun notarytool store-credentials --help
  ```

* `--keychain=<path>` (optional)

  When used in conjunction with `--keychain-profile`, the script will pass
  this option through to Apple's `notarytool` (it tells notarytool which
  keychain the profile is in).

Example
-------

    $ ./fetch-emacs-from-ftp -v ftp://ftp.gnu.org/pub/gnu/emacs
    + curl --continue-at - --silent -O ftp://ftp.gnu.org/pub/gnu/emacs/emacs-25.1.tar.xz
    $ ls *.xz
    emacs-25.1.tar.xz
    $ ./build-emacs-from-tar -v -j 8 emacs-25.1.tar.xz release
      ... Lots out output snipped ...
    Built Emacs-25.1-10.12-x86_64.tar.xz, Emacs-25.1-10.12-x86_64-dependencies.tar
    $ ./combine-and-package -v Emacs-25.1-10.12-x86_64.tar.xz
      ... More output snipped ...
    created: Emacs-25.1-universal.dmg

License
-------

Copyright © 2004-2025 David Caldwell <david@porkrind.org>

The scripts and programs contained in this distribution are licensed under
the GNU General Public License (v3.0). See the LICENSE file for details.
