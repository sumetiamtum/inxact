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

	apt-get -q -y update
	apt-get -q -y upgrade
	apt-get -q -y dist-upgrade
	rm /etc/apt/sources.list
	cat > sources.list << EOF
deb http://httpredir.debian.org/debian stretch main
deb http://httpredir.debian.org/debian stretch-updates main
deb http://security.debian.org stretch/updates main
EOF
	mv sources.list /etc/apt/
	apt-get -q -y update
	apt-get -q -y upgrade
	apt-get dist-upgrade
	reboot
