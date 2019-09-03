#!/bin/sh

if [ $# -lt 1 ];then
	echo "Usage: $(basename $0) emacs-xxx.tar.bz2"
	exit 1
fi

export CFLAGS=-O2
./build-emacs-from-tar -v --no-brew $1 "release"

#./combine-and-package -v Emacs-26.0.90-10.13-x86_64.tar.bz2

