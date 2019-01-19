	#!/bin/bash
  # Remove apache2
  	sudo service apache2 stop
	sudo apt-get purge apache2 apache2-utils apache2.2-bin apache2-common
	sudo apt-get autoremove
	sudo rm -rf /etc/apache2
  # Remove bind9
	apt-get remove -y bind9
  # Update ubuntu
	apt-get -q -y update
	apt-get -q -y upgrade
  # Install basic task software
	apt-get install -q -y sudo
	sudo apt-get install -q -y rsync
	sudo apt-get install -q -y nano
