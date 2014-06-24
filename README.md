Emacs Build Script
==================

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

    DIR=emacs-$BUILD_ID-$BZR_REVISION
    rm -rf emacs-*
    bzr checkout --lightweight . $DIR
    (cd $DIR && ./autogen.sh)
    tar cjf $DIR.tar.bz2 --exclude '.bzr' $DIR


### combine-and-package

This takes multiple tar files as input, unpacks and combines them into a
final "fat" Emacs.app, then creates a final disk image (`.dmg`). It takes an
optional `--sign` parameter (`--sign="my identity"`) which makes it code
sign the Emacs.app.


License
-------

Copyright © 2004-2014 David Caldwell <david@porkrind.org>

The scripts and programs contained in this distribution are licensed under
the GNU General Public License (v3.0). See the LICENSE file for details.
