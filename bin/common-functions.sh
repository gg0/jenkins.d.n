#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

common_cleanup(){
	echo "$(date) - $0 stopped running as $TTT, which will now be removed."
	rm -f $TTT
}

common_init() {
# check whether this script has been started from /tmp already
if [ "${0:0:5}" != "/tmp/" ] ; then
	# mktemp some place for us...
	TTT=$(mktemp --tmpdir=/tmp jenkins-script-XXXXXXXX)
	# prepare cleanup
	trap common_cleanup INT TERM EXIT
	# cp $0 to /tmp and run it from there
	cp $0 $TTT
	chmod +x $TTT
	# run ourself with the same parameter as we are running
	# but run a copy from /tmp so that the source can be updated
	# (Running shell scripts fail weirdly when overwritten when running,
	#  this hack makes it possible to overwrite long running scripts
	#  anytime...)
	echo "$(date) - start running \"$0\" as \"$TTT\" using \"$@\" as arguments."
	$TTT "$@"
	exit $?
	# cleanup is done automatically via trap
else
	# default settings used for the jenkins.debian.net environment
	if [ -z "$LC_ALL" ]; then
		export LC_ALL=C
	fi
	if [ -z "$MIRROR" ]; then
		export MIRROR=http://ftp.de.debian.org/debian
	fi
	if [ -z "$http_proxy" ]; then
		export http_proxy="http://localhost:3128"
	fi
	if [ -z "$CHROOT_BASE" ]; then
		export CHROOT_BASE=/chroots
	fi
	if [ -z "$SCHROOT_BASE" ]; then
		export SCHROOT_BASE=/schroots
	fi

	# throw-away logical volumes options
	export VGNAME=jenkins01
	export MNTFSTYPE=ext4
	export MNTOPTS=nobarrier,commit=300,delalloc,data=writeback,relatime

	# use these settings in the scripts in the (s)chroots too
	export SCRIPT_HEADER="#!/bin/bash
	set -e
	set -x
	export DEBIAN_FRONTEND=noninteractive
	export LC_ALL=$LC_ALL
	export http_proxy=$http_proxy
	export MIRROR=$MIRROR"
	# be more verbose
	export
	set -e
	set -x
fi
}

