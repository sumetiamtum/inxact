#!/bin/bash
# Start with a clean install

function check_sanity {
    # This first part makes sure that the bash script is being executed by root
    if [ $(/usr/bin/id -u) != "0" ]
    then
		die 'Must be run by root user'
    fi

    if [ ! -f /etc/debian_version ]
    then
        die "Distribution is not supported"
    fi
}
 	echo Update sources
	apt-get -q -y update
	echo Upgrade what can be upgraded
	apt-get -q -y upgrade
	echo Now the Distribution upgrade
	apt-get -q -y dist-upgrade
	echo Remove the Sources.List - they include old sources
	rm /etc/apt/sources.list
	echo Done. Now create new sources
	echo http://httpredir.debian.org/debian stretch main
	echo http://httpredir.debian.org/debian stretch main
	echo http://security.debian.org stretch/updates main
	cat > sources.list << EOF
deb http://httpredir.debian.org/debian stretch main
deb http://httpredir.debian.org/debian stretch-updates main
deb http://security.debian.org stretch/updates main
EOF
	echo Moving sources list to the /etc/apt folder
	mv sources.list /etc/apt/
	echo Update new sources
	apt-get -q -y update
	echo Upgrade everything again
	apt-get -q -y upgrade
	echo Upgrade the distribution to Stretch
	apt-get dist-upgrade
	echo About to reboot
	sleep 3
	reboot
