#!/bin/bash
 function install_mysql {
    # Install the MySQL packages
    apt-get -q -y install mariadb-server mariadb-client

    # Generating a new password for the root user.
    passwd=`get_password root@mysql`
    mysqladmin password "$passwd"
	# this creates the .my.cnf file and places it in the user directory
	# By using this next time you run mysql commands mysql, mysqlcheck, 
	# mysqdump, etc; they will pick username & password from this file if
	# you do not provide them as argument (-u and -p). It can save your time
	# and allows the script to create a Wordpress Database and User without
	# requiring a reinput of the MySQL root password.
    cat > ~/.my.cnf <<END
[client]
user = root
password = $passwd
END
    chmod 600 ~/.my.cnf
}

function get_password() {
    # Check whether our local salt is present.
    SALT=/var/lib/radom_salt
    if [ ! -f "$SALT" ]
    then
        head -c 512 /dev/urandom > "$SALT"
        chmod 400 "$SALT"
    fi
    password=`(cat "$SALT"; echo $1) | md5sum | base64`
    echo ${password:0:13}
}



 
 # Program
 export PATH=/bin:/usr/bin:/sbin:/usr/sbin
 
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
# Install mysql
install_mysql
#Install nginx
apt-get -q -y install nginx
sudo rm /etc/nginx/sites-enabled/default
invoke-rc.d nginx restart
# Install PHP7.0
sudo apt-get -q -y install php-fpm
sudo apt-get -q -y install php-gd php-curl php-mysql php-ssh2 php-mbstring php-mcrypt php-xml php-xmlrpc
sudo service php7.0-fpm restart
