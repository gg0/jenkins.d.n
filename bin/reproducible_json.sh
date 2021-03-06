#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set +x

write_json() {
	echo "$1" >> $JSON
}

JSON=$(mktemp)
RESULT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name,version,status FROM source_packages WHERE status != \"\"")
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status != \"\"")
echo "$(date) - processing $COUNT_TOTAL packages to create .json output... this will take a while."

write_json "["
for LINE in $RESULT ; do
	PKG=$(echo $LINE | cut -d "|" -f1)
	VERSION=$(echo $LINE | cut -d "|" -f2)
	STATUS=$(echo $LINE | cut -d "|" -f3)
	if [ "$STATUS" = "unreproducible" ] ; then
	        if [ -f /var/lib/jenkins/userContent/buildinfo/${PKG}_${VERSION}_amd64.buildinfo ] ; then
			STATUS="$STATUS-with-buildinfo"
		fi
	fi
	write_json "{"
	write_json "\"package\": \"$PKG\","
	write_json "\"version\": \"$VERSION\","
	write_json "\"status\": \"$STATUS\","
	write_json "\"suite\": \"sid\""
	write_json "}"
done
write_json "]"

echo
echo "$(date) - $JENKINS_URL/userContent/reproducible.json has been updated."
mv $JSON /var/lib/jenkins/userContent/reproducible.json
chmod 755 /var/lib/jenkins/userContent/reproducible.json
