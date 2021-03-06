#!/bin/bash

# Copyright 2012-2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

BASEDIR=/root/jenkins.debian.net
PVNAME=/dev/vdb      # LVM physical volume for jobs
VGNAME=jenkins01     # LVM volume group

explain() {
	echo
	echo $1
	echo
}

mkdir -p /srv/workspace

if ! grep -q '^tmpfs\s\+/srv/workspace\s' /etc/fstab; then
	echo "tmpfs		/srv/workspace	tmpfs	defaults,size=60g	0	0" >> /etc/fstab
fi

if ! mountpoint -q /srv/workspace; then
	if test -z "$(ls -A /srv/workspace)"; then
		mount /srv/workspace
	else
		echo "mountpoint /srv/workspace is non-empty"
	fi
fi

# make sure needed directories exists
for directory in  /srv/jenkins /schroots /srv/reproducible-results /srv/d-i ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins.jenkins $directory
	fi
done

if ! test -h /chroots; then
	rmdir /chroots || rm -f /chroots # do not recurse
	if test -e /chroots; then
		echo could not clear /chroots
	else
		ln -s /srv/workspace/chroots /chroots
	fi
fi

if ! test -h /var/cache/pbuilder/build; then
	rmdir /var/cache/pbuilder/build || rm -f /var/cache/pbuilder/build
	if test -e /var/cache/pbuilder/build; then
		echo could not clear /var/cache/pbuilder/build
	else
		ln -s /srv/workspace/pbuilder /var/cache/pbuilder/build
	fi
fi

#
# install packages we need
# (more or less grouped into more-then-nice-to-have, needed-while-things-are-new, needed)
#
sudo apt-get install vim screen less etckeeper moreutils curl mtr-tiny dstat devscripts bash-completion shorewall shorewall6 cron-apt apt-listchanges munin munin-plugins-extra calamaris visitors procmail libjson-rpc-perl libfile-touch-perl zutils ip2host pigz \
	build-essential python-setuptools \
	debootstrap sudo figlet graphviz apache2 python-yaml python-pip mr subversion subversion-tools vnstat poxml vncsnapshot imagemagick libav-tools python-twisted python-imaging gocr guestmount schroot sqlite3\
	unzip python-hachoir-metadata ghc python-rpy2 libsoap-lite-perl haveged postgresql-client-9.1
# debootstrap is affected by #766459 in wheezy
sudo apt-get install -t wheezy-backports qemu debootstrap
explain "Packages installed."

#
# deploy package configuration in /etc
#
cd $BASEDIR
sudo cp -r etc/* /etc

#
# more configuration than a simple cp can do
#
if [ ! -e /etc/apache2/mods-enabled/proxy.load ] ; then
	sudo a2enmod proxy
	sudo a2enmod proxy_http
	sudo a2enmod rewrite
	sudo a2enmod ssl
	sudo a2enmod headers
fi
sudo chown root.root /etc/sudoers.d/jenkins ; sudo chmod 700 /etc/sudoers.d/jenkins
sudo ln -sf /etc/apache2/sites-available/jenkins.debian.net /etc/apache2/sites-enabled/000-default
sudo service apache2 reload
cd /etc/munin/plugins ; sudo rm -f postfix_* open_inodes df_inode interrupts irqstats threads proc_pri vmstat if_err_eth0 fw_forwarded_local fw_packets forks open_files users 2>/dev/null
[ -L apache_accesses ] || for i in apache_accesses apache_volume ; do ln -s /usr/share/munin/plugins/$i $i ; done
explain "Packages configured."
sudo service munin-node force-reload

#
# install the heart of jenkins.debian.net
#
cd $BASEDIR
cp -r bin logparse job-cfg /srv/jenkins/
cp procmailrc /var/lib/jenkins/.procmailrc
explain "Jenkins updated."
cp -pr README INSTALL TODO d-i-preseed-cfgs /var/lib/jenkins/userContent/
cp -pr userContent /var/lib/jenkins/
cd /var/lib/jenkins/userContent/
ASCIIDOC_PARAMS="-a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -b html5 -a toc -a toclevels=4 -a icons -a stylesheet=$(pwd)/theme/debian-asciidoc.css"
[ about.html -nt README ] || asciidoc $ASCIIDOC_PARAMS -o about.html README
[ todo.html -nt TODO ] || asciidoc $ASCIIDOC_PARAMS -o todo.html TODO
[ setup.html -nt INSTALL ] || asciidoc $ASCIIDOC_PARAMS -o setup.html INSTALL
rm TODO README INSTALL
chown -R jenkins.jenkins /var/lib/jenkins/userContent
explain "Updated user content for Jenkins."

#
# run jenkins-job-builder to update jobs if needed
#     (using sudo because /etc/jenkins_jobs is root:root 700)
#
cd /srv/jenkins/job-cfg
for metaconfig in *.yaml.py ; do
	python $metaconfig > ${metaconfig%.py}
done
for config in *.yaml ; do
	sudo jenkins-jobs update $config
done
explain "Jenkins jobs updated."

#
# crappy tests for checking that jenkins-job-builder works correctly
#
#wc -m counts one byte too many, so we substract one
let DEFINED_MY_TRIGGERS=$(grep my_trigger: *.yaml|wc -l)+$(grep my_trigger: *.yaml|grep , |xargs -r echo | sed 's/[^,]//g'| wc -m)-1
DEFINED_DI_TRIGGERS=$(grep "defaults: d-i-manual-html" d-i.yaml|wc -l)
#DEFINED_REPRODUCIBLE_TRIGGERS=$(grep "^    defaults: reproducible$" reproducible.yaml|wc -l)
let DEFINED_TRIGGERS=DEFINED_MY_TRIGGERS+DEFINED_DI_TRIGGERS
#let DEFINED_TRIGGERS=DEFINED_TRIGGERS+DEFINED_REPRODUCIBLE_TRIGGERS
let CONFIGURED_TRIGGERS=$(grep \<childProjects /var/lib/jenkins/jobs/*/config.xml|wc -l)+$(grep  \<childProjects /var/lib/jenkins/jobs/*/config.xml |grep , |xargs -r echo | sed 's/[^,]//g'| wc -m)-1
if [ "$DEFINED_TRIGGERS" != "$CONFIGURED_TRIGGERS" ] ; then
	figlet -f banner Warning
	explain "Number of defined triggers ($DEFINED_TRIGGERS) differs from currently configured triggers ($CONFIGURED_TRIGGERS), please investigate."
fi

#
# configure git for jenkins
#
if [ "$(sudo su - jenkins -c 'git config --get user.email')" != "jenkins@jenkins.debian.net" ] ; then
	sudo su - jenkins -c "git config --global user.email jenkins@jenkins.debian.net"
	sudo su - jenkins -c "git config --global user.name Jenkins"
fi
#
# FIXME: file a bug against pbuilder
#	else you have https://jenkins.debian.net/view/debian-installer/job/d-i_build_partman-ext3/4/console
#	with this you have: https://jenkins.debian.net/view/debian-installer/job/d-i_build_partman-ext3/5/console
#	and this asks for a password: pdebuild --use-pdebuild-internal --pbuilder '/sbin/sudo /usr/sbin/pbuilder'
#	despites the jenkins user cam run "sudo pbuilder" without it just fine...??!
#
sudo chown jenkins /var/cache/pbuilder/result

#
# There's always some work left...
#	echo FIXME is ignored so check-jobs scripts can output templates requiring manual work
#
echo
rgrep FIXME $BASEDIR/* | grep -v "rgrep FIXME" | grep -v echo

#
# creating LVM volume group for jobs
#
if [ "$PVNAME" = "" ]; then
    figlet -f banner Error
    explain "Set \$PVNAME to physical volume pathname."
    exit 1
else
    if ! sudo pvs $PVNAME >/dev/null 2>&1; then
        sudo pvcreate $PVNAME
    fi
    if ! sudo vgs $VGNAME >/dev/null 2>&1; then
        sudo vgcreate $VGNAME $PVNAME
    fi
fi
