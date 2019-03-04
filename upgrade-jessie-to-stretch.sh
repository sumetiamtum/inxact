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
 	echo -e "\e[31Update sources\e[0m"
	apt-get -q -y update
	echo -e "\e[31Upgrade what can be upgraded\e[0m"
	apt-get -q -y upgrade
	echo -e "\e[31Now the Distribution upgrade\e[0m"
	apt-get -q -y dist-upgrade
	echo -e "\e[31Removing the old sources.list - they include old sources\e[0m"
	rm /etc/apt/sources.list
	echo -e "\e[31Done. Now create new sources\e[0m"
	echo -e "\e[31http://httpredir.debian.org/debian stretch main\e[0m"
	echo -e "\e[31http://httpredir.debian.org/debian stretch main\e[0m"
	echo -e "\e[31http://security.debian.org stretch/updates main\e[0m"
	cat > sources.list << EOF
deb http://httpredir.debian.org/debian stretch main
deb http://httpredir.debian.org/debian stretch-updates main
deb http://security.debian.org stretch/updates main
EOF
	echo -e "\e[31Moving sources list to the /etc/apt folder\e[0m"
	mv sources.list /etc/apt/
	echo -e "\e[31Update new sources\e[0m"
	apt-get -q -y update
	echo -e "\e[31Upgrade everything again\e[0m"
	apt-get -q -y upgrade
	echo -e "\e[31Upgrade the distribution to Stretch\e[0m"
	apt-get dist-upgrade
	echo -e "\e[31About to reboot\e[0m"
	sleep 3
	reboot
