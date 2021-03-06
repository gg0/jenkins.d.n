#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

set +x
init_html

VIEW=dd-list
PAGE=index_${VIEW}.html
echo "$(date) - starting to write $PAGE page."
write_page_header $VIEW "Overview of ${SPOKENTARGET[$VIEW]}"
TMPFILE=$(mktemp)
BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY build_date DESC" | xargs echo)
echo "${BAD}" | dd-list -i > $TMPFILE || true
write_page "<p>The following maintainers and uploaders are listed for packages which have built unreproducibly:</p><p><pre>"
while IFS= read -r LINE ; do
	if [ "${LINE:0:3}" = "   " ] ; then
		PACKAGE=$(echo "${LINE:3}" | cut -d " " -f1)
		UPLOADERS=$(echo "${LINE:3}" | cut -d " " -f2-)
		if [ "$UPLOADERS" = "$PACKAGE" ] ; then
			UPLOADERS=""
		fi
		write_page "   <a href=\"$JENKINS_URL/userContent/rb-pkg/$PACKAGE.html\">$PACKAGE</a> $UPLOADERS"
	else
		LINE="$(echo $LINE | sed 's#&#\&amp;#g ; s#<#\&lt;#g ; s#>#\&gt;#g')"
		write_page "$LINE"
	fi
done < $TMPFILE
write_page "</pre></p>"
rm $TMPFILE
write_page_footer
publish_page

