#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# $1 = base distro
# $2 = extra component
# $3 = upgrade distro

if [ "$1" == "" ] ; then
	echo "need at least one distribution to act on"
	echo '# $1 = base distro'
	echo '# $2 = extra component (gnome, kde, xfce, lxce)'
	echo '# $3 = upgrade distro'
	exit 1
fi

SLEEP=$(shuf -i 1-10 -n 1)
echo "Sleeping $SLEEP seconds to randomize start times and parallel runs."
sleep $SLEEP

export CHROOT_TARGET=$(mktemp -d -p /chroots/ chroot-installation-$1.XXXXXXXXX)
export TMPFILE=$(mktemp -u)
export CTMPFILE=$CHROOT_TARGET/$TMPFILE

#
# mount LV
#
LVNAME=$(basename $CHROOT_TARGET)
LVPATH=/dev/${VGNAME}/$LVNAME
LVSIZE=10
echo "Creating throw-away logical volume with ${LVSIZE} GiB now."
sudo lvcreate -L${LVSIZE}G -n $LVNAME $VGNAME
echo "Creating filesystem on $LVPATH now."
sudo mkfs -t $FSTYPE $LVPATH
echo "Mounting logical volume $LVNAME under $CHROOT_TARGET now."
sudo mount -o $MNTOPTS $LVPATH $CHROOT_TARGET

cleanup_all() {
	# test if $CHROOT_TARGET starts with /chroots/
	if [ "${CHROOT_TARGET:0:9}" != "/chroots/" ] ; then
		echo "HALP. CHROOT_TARGET = $CHROOT_TARGET"
		exit 1
	fi
	sudo umount -l $CHROOT_TARGET/proc || fuser -mv $CHROOT_TARGET/proc
	sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
}

execute_ctmpfile() {
	chmod +x $CTMPFILE
	sudo chroot $CHROOT_TARGET $TMPFILE & wait $!
	rm $CTMPFILE
}

prepare_bootstrap() {
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
mount /proc -t proc /proc
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
echo "Acquire::http::Proxy \"$http_proxy\";" > /etc/apt/apt.conf.d/80proxy
echo "deb-src $MIRROR $1 main contrib non-free" >> /etc/apt/sources.list
apt-get update
EOF
}

prepare_install_packages() {
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
apt-get -y install $@
EOF
}

prepare_install_build_depends() {
	cat >> $CTMPFILE <<-EOF
$SCRIPT_HEADER
apt-get -y install build-essential
EOF
for PACKAGE in $@ ; do
	echo apt-get -y build-dep $PACKAGE >> $CTMPFILE
done
}

prepare_upgrade2() {
	cat >> $CTMPFILE <<-EOF
echo "deb $MIRROR $1 main contrib non-free" >> /etc/apt/sources.list
$SCRIPT_HEADER
apt-get update
apt-get -y upgrade
apt-get -yf dist-upgrade
apt-get -yf dist-upgrade
apt-get -y autoremove
EOF
}

bootstrap() {
	sudo mkdir -p "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io | sudo tee "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	echo "Bootstrapping $1 into $CHROOT_TARGET now."
	sudo debootstrap $1 $CHROOT_TARGET $MIRROR & wait $!
	prepare_bootstrap $1
	execute_ctmpfile 
}

install_packages() {
	echo "Installing extra packages for $1 now."
	shift
	prepare_install_packages $@
	execute_ctmpfile 
}

install_build_depends() {
	echo "Installing build depends for $1 now."
	shift
	prepare_install_build_depends $@
	execute_ctmpfile
}

upgrade2() {
	echo "Upgrading to $1 now."
	prepare_upgrade2 $1
	execute_ctmpfile 
}

trap cleanup_all INT TERM EXIT

case $1 in
	squeeze)	DISTRO="squeeze"
			SPECIFIC="openoffice.org virtualbox-ose mplayer chromium-browser"
			;;
	wheezy)		DISTRO="wheezy"
			SPECIFIC="libreoffice virtualbox mplayer chromium"
			;;
	jessie)		DISTRO="jessie"
			SPECIFIC="libreoffice virt-manager mplayer2 chromium"
			;;
	sid)		DISTRO="sid"
			SPECIFIC="libreoffice virt-manager mplayer2 chromium"
			;;
	*)		echo "unsupported distro."
			exit 1
			;;
esac
bootstrap $DISTRO

if [ "$2" != "" ] ; then
	FULL_DESKTOP="$SPECIFIC desktop-base gnome kde-plasma-desktop kde-full kde-standard xfce4 lxde vlc evince iceweasel cups build-essential devscripts wine texlive-full asciidoc vim emacs"
	case $2 in
		none)		;;
		gnome)		install_packages gnome gnome desktop-base
				;;
		kde)		install_packages kde kde-plasma-desktop desktop-base
				;;
		kde-full)	install_packages kde kde-full kde-standard desktop-base
				;;
		xfce)		install_packages xfce xfce4 desktop-base
				;;
		lxde)		install_packages lxde lxde desktop-base
				;;
		full_desktop)	install_packages full_desktop $FULL_DESKTOP
				;;
		haskell)	install_packages haskell 'haskell-platform.*' 'libghc-.*'
				;;
		developer)	install_build_depends developer $FULL_DESKTOP
				;;
		*)		echo "unsupported component."
				exit 1
				;;
	esac
fi

if [ "$3" != "" ] ; then
	case $3 in
		squeeze)upgrade2 squeeze;;
		wheezy)	upgrade2 wheezy;;
		jessie)	upgrade2 jessie;;
		sid)	upgrade2 sid;;
		*)	echo "unsupported distro." ; exit 1 ;;
	esac
fi

cleanup_all
trap - INT TERM EXIT

