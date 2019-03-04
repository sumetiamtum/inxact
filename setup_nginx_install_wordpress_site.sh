#!/bin/bash

########################################################################
# These functions are background tasks to sort stop the script
# or print on the screen or creates a password
########################################################################
function install_ufw {
	echo Installing UFW
	check_install ufw ufw
	# set default rules to prevent all incoming traffic
	sudo ufw default deny incoming
	sudo ufw default allow outgoing
	# allow shell connections
	sudo ufw allow ssh
	sudo ufw allow "Nginx HTTP"
	sudo ufw allow "Nginx HTTPS"
	# enable ufw
	sudo ufw enable
}

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

function die {
    echo "ERROR: $1" > /dev/null 1>&2
    exit 1
}

function print_info {
    echo -n -e '\e[1;36m'
    echo -n $1
    echo -e '\e[0m'
}

function print_warn {
    echo -n -e '\e[1;33m'
    echo -n $1
    echo -e '\e[0m'
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
    echo ${password:0:16}
}

function install_dash {
	check_install dash dash
    rm -f /bin/sh
    ln -s dash /bin/sh
}

function install_syslogd {
    # We just need a simple vanilla syslogd. Also there is no need to log to
    # so many files (waste of fd). Just dump them into
    # /var/log/(cron/mail/messages)
    check_install /usr/sbin/syslogd inetutils-syslogd
    invoke-rc.d inetutils-syslogd stop

    for file in /var/log/*.log /var/log/mail.* /var/log/debug /var/log/syslog
    do
        [ -f "$file" ] && rm -f "$file"
    done
    for dir in fsck news
    do
        [ -d "/var/log/$dir" ] && rm -rf "/var/log/$dir"
    done
    # This next section creates a syslog.conf file and writes to it
    cat > /etc/syslog.conf <<END
*.*;mail.none;cron.none -/var/log/messages
cron.*                  -/var/log/cron
mail.*                  -/var/log/mail
END

    [ -d /etc/logrotate.d ] || mkdir -p /etc/logrotate.d
    cat > /etc/logrotate.d/inetutils-syslogd <<END
/var/log/cron
/var/log/mail
/var/log/messages {
   rotate 4
   weekly
   missingok
   notifempty
   compress
   sharedscripts
   postrotate
      /etc/init.d/inetutils-syslogd reload >/dev/null
   endscript
}
END

    invoke-rc.d inetutils-syslogd start
}

function get_domain_name() {
    # Getting rid of the lowest part.
    domain=${1%.*}
    lowest=`expr "$domain" : '.*\.\([a-z][a-z]*\)'`
    case "$lowest" in
    com|net|org|gov|edu|co)
        domain=${domain%.*}
        ;;
    esac
    lowest=`expr "$domain" : '.*\.\([a-z][a-z]*\)'`
    [ -z "$lowest" ] && echo "$domain" || echo "$lowest"
}
########################################################################

########################################################################
# This function installs the $1 application
########################################################################
function check_install {
    if [ -z "`which "$1" 2>/dev/null`" ]
    then
        executable=$1
        shift
        while [ -n "$1" ]
        do
        print_info "Installing $1"
	    DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
            print_info "$1 installed"
            shift
	    sleep 2
        done
    else
        print_warn "$2 already installed"
    fi
}
########################################################################

########################################################################
# Installs necessary applications
########################################################################
function update_upgrade_install {
	# Run through the apt-get update/upgrade first. This should be done before
	# any package is installed
	apt-get -q -y update
	sleep 2
	apt-get -q -y upgrade
	sleep 2
	# install needed administrative programs
	check_install sudo sudo
	check_install rsync rsync
	check_install nano nano
	check_install net-tools net-tools
	check_install wget wget
	check_install curl curl
	check_install bash-completion bash-completion
	check_install cron cron
}
########################################################################

########################################################################
# Install relevant php modules
########################################################################
function install_php {
	check_install php5-fpm php5-fpm
	check_install php5-mysql php5-mysql
	check_install php5-curl
	check_install libssh2-php
	# This changes the cgi.fix_pathinfo setting to a more secure level
	sed -i "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php5/fpm/php.ini
	# Restart it to bring the changes into effect
	sudo systemctl restart php5-fpm
}
########################################################################

########################################################################
# Install nginx
########################################################################
function install_nginx {
    check_install nginx nginx
    
	cd ~
    # Disable the default server block
    # sudo rm /etc/nginx/sites-enabled/default
	# Remove the old nginx default file
	# Insert blank html file
	sudo rm /var/www/html/index.nginx-debian.html
	wget --no-check-certificate https://raw.githubusercontent.com/sumetiamtum/inxact/master/index.html
	mv index.html /var/www/html/
	# Get the nginx/wordpress config file and replace the existing file with this one
	wget --no-check-certificate https://raw.githubusercontent.com/sumetiamtum/inxact/master/nginx_wordpress_conf
	cp nginx_wordpress_conf /etc/nginx/nginx.conf
	rm -r nginx_wordpress_conf
	sudo service nginx restart
	# Later we need to set up a server block for any websites	
	# Restart the server to bring changes into effect
    invoke-rc.d nginx restart
}
########################################################################


########################################################################
# Installs wordpress and creates the MariaDB database
# It has become an all in one with the 
########################################################################
function install_wordpress {
	# just making sure wget is installed
    check_install wget wget
    # Need a domain name or otherwise quit
	if [ -z "$1" ]
    then
        die "Usage: `basename $0` wordpress <hostname>"
    fi

    # Create the necessary folder structure
	sudo mkdir -p /var/www/html/$1/{public_html,private,logs,cgi-bin,backup}
	
	
    # We should change the ownership of this directory
    sudo chown -R www-data:www-data /var/www/html/$1/public_html/
    # Set the read permissions to the Apache2 web root (/var/www/html/)
	# directory, so that everyone can read files from that directory.
    sudo chmod -R 755 /var/www/html
	
    # Downloading the WordPress' latest and greatest distribution.
    # Go back to root directory
    cd ~
    # Download, unpack and configure WordPress
    wget http://wordpress.org/latest.tar.gz
    tar xzvf latest.tar.gz
    cd ~/wordpress
    
	# This section creates the MariaDB database
	# First we need to decide what to call our database
    dbname=`echo $1 | tr . _`
    # Use the domain name without the TLD part as the username
	userid=`get_domain_name $1`
	    # MySQL userid cannot be more than 15 characters long
    userid="${userid:0:15}"
    passwd=`get_password "$userid@mysql"`
    
    # Create the database, user and password access	
    mysqladmin create "$dbname"
    echo "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO \`$userid\`@localhost IDENTIFIED BY '$passwd';" | \
        mysql
    echo "FLUSH PRIVILEGES;"| \
        mysql
		
	#Set up the wordpress config file with the mySQL database details
    cp wp-config-sample.php wp-config.php
    chmod 640 wp-config.php
    # Replace the necessary MariaDB database details in the Wordpress config.php
	# Also set memory limit so there are no problems
	sed -i "s/database_name_here/$dbname/; s/username_here/$userid/; s/password_here/$passwd/; s/define( 'WP_DEBUG', false );/define( 'WP_DEBUG', false );\ndefine( 'WP_MEMORY_LIMIT', '300M' );/" wp-config.php
	
    #Copy the wordpress files over to the domain root
    sudo rsync -avP ~/wordpress/ /var/www/html/$1/public_html/
	
    #Move to the domain root to set some permissions
    cd /var/www/html/$1/public_html/
    sudo chown -R www-data:www-data /var/www/html/$1/public_html/*
	
    #Create the uploads directory and establish permissions
    mkdir /var/www/html/$1/public_html/wp-content/uploads
    cd /var/www/html/$1/public_html/wp-content/uploads
    sudo chown -R :www-data /var/www/html/$1/public_html/wp-content/uploads
    sudo chmod -R ugo+rw /var/www/html/$1/public_html/wp-content/uploads
    cd /var/www/html/$1/public_html
    sudo chmod -R ugo+rw /var/www/html/$1/public_html
    
	# Return to the root directory and remove temporary files
	cd ~
	rm -r wordpress latest.tar.gz
	
	# Now we need to set up the nginx server block for the domain
	# First we take a pull from our github respository an example file
	# copy the server block over to /etc/nginx/sites-available and rename to the domain
	wget --no-check-certificate https://raw.githubusercontent.com/sumetiamtum/inxact/master/nginx_wordpress_server_block
  	cp nginx_wordpress_server_block /etc/nginx/sites-available/$1
	rm nginx_wordpress_server_block
	
 	# make sure the folder reference removes [example] and insert the right location
	sed -i "s/!example!/$1/" /etc/nginx/sites-available/$1

	# ask for input on whether the domain is www or not
	while true; do
		read -p "domain.com (1) or www.domain.com (2)?" yn
		case $yn in
			1 )
				sed -i "s/!example.com!/www.$1/; s/!www.example.com!/$1/" /etc/nginx/sites-available/$1
				break
				;;
			2 )
				sed -i "s/!www.example.com!/www.$1/; s/!example.com!/$1/" /etc/nginx/sites-available/$1
				break
				;;
			* ) echo "Please choose (1) or (2)."
				;;
		esac
	done
	
	#Enable the new server block
    sudo ln -s /etc/nginx/sites-available/$1 /etc/nginx/sites-enabled/
	
    #Restart the nginx service
    sudo service nginx restart
	
	#Restart the php5-fpm service
    sudo service php5-fpm restart
	
    # return to the root directory
	cd ~
  
	# Finally install the https certificate
	# sudo certbot --apache -d $1 -d www.$1
}

########################################################################
# Install MariaDB and create root password
########################################################################
function install_mariadb {
	# Install the MySQL packages
    check_install mariadb-server mariadb-server
	check_install mariadb-client mariadb-client
	systemctl start mariadb
    # Generating a new password for the root user.
    passwd=`get_password root@mysql`
    mysqladmin password "$passwd"
	echo "The password is $passwd"
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
########################################################################

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

	check_sanity

case "$1" in
system)
	update_upgrade_install
	install_dash
	install_syslogd
	install_exim4
	install_nginx
	install_php
	install_mariadb
	install_ufw
	;;
wordpress)	
	install_wordpress $2
	;;
esac

