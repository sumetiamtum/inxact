#!/bin/bash

function remove_unneeded {
    # Some Debian have portmap installed. We don't need that.
    check_remove /sbin/portmap portmap

    # Remove rsyslogd, which allocates ~30MB privvmpages on an OpenVZ system,
    # which might make some low-end VPS inoperatable. We will do this even
    # before running apt-get update.
    check_remove /usr/sbin/rsyslogd rsyslog

    # Other packages that seem to be pretty common in standard OpenVZ
    # templates.
    check_remove /usr/sbin/apache2 'apache2*'
    check_remove /usr/sbin/named bind9
    check_remove /usr/sbin/smbd 'samba*'
    check_remove /usr/sbin/nscd nscd

    # Need to stop sendmail as removing the package does not seem to stop it.
    if [ -f /usr/lib/sm.bin/smtpd ]
    then
        invoke-rc.d sendmail stop
        check_remove /usr/lib/sm.bin/smtpd 'sendmail*'
    fi
}

function update_upgrade {
    # Run through the apt-get update/upgrade first. This should be done before
    # we try to install any package
    apt-get -q -y update
    apt-get -q -y upgrade
    apt-get install -q -y sudo
    sudo apt-get install -q -y rsync
    sudo apt-get install -q -y nano
}

function install_dash {
    check_install dash dash
    rm -f /bin/sh
    ln -s dash /bin/sh
}

function install_dropbear {
    check_install dropbear dropbear
    check_install /usr/sbin/xinetd xinetd

    # Disable SSH
    touch /etc/ssh/sshd_not_to_be_run
    invoke-rc.d ssh stop

    # Enable dropbear to start. We are going to use xinetd as it is just
    # easier to configure and might be used for other things.
    cat > /etc/xinetd.d/dropbear <<END
service ssh
{
    socket_type     = stream
    only_from       = 0.0.0.0
    wait            = no
    user            = root
    protocol        = tcp
    server          = /usr/sbin/dropbear
    server_args     = -i
    disable         = no
}
END
    invoke-rc.d xinetd restart
}

function check_sanity {
    # Do some sanity checking.
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

function check_install {
    if [ -z "`which "$1" 2>/dev/null`" ]
    then
        executable=$1
        shift
        while [ -n "$1" ]
        do
            DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1"
            print_info "$1 installed for $executable"
            shift
        done
    else
        print_warn "$2 already installed"
    fi
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

function check_remove {
    if [ -n "`which "$1" 2>/dev/null`" ]
    then
        DEBIAN_FRONTEND=noninteractive apt-get -q -y remove --purge "$2"
        print_info "$2 removed"
    else
        print_warn "$2 is not installed"
    fi
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

function install_mysql {
    # Install the MySQL packages
    check_install mariadb-server mariadb-client
#   check_install mysql mysql-client

    # Install a low-end copy of the my.cnf to disable InnoDB, and then delete
    # all the related files.
#    invoke-rc.d mysql stop
#    rm -f /var/lib/mysql/ib*
#    cat > /etc/mysql/conf.d/lowendbox.cnf <<END
#[mysqld]
#key_buffer = 8M
#query_cache_size = 0
#skip-innodb
#END
#    invoke-rc.d mysql start

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

function install_nginx {
    check_install nginx nginx
    
    #Disable the default server block
    sudo rm /etc/nginx/sites-enabled/default

    invoke-rc.d nginx restart
}

function install_wordpress {
    check_install wget wget
    if [ -z "$1" ]
    then
        die "Usage: `basename $0` wordpress <hostname>"
    fi

    #Create the necessary folder structure
    sudo mkdir -p /var/www/html/$1/public_html
    #We should change the ownership of this directory
    sudo chown -R $USER:$USER /var/www/html/$1/public_html/
    #Set the read permissions to the Nginx web root (/var/www/html/) directory, so that everyone can read files from that directory.
    sudo chmod -R 755 /var/www/html/
    # Downloading the WordPress' latest and greatest distribution.
    #Go back to root directory
    cd ~
    # Download, unpack and configure WordPress
    wget http://wordpress.org/latest.tar.gz
    tar xzvf latest.tar.gz
    cd ~/wordpress
    
    # Setting up the MySQL database
    dbname=`echo $1 | tr . _`
    userid=`get_domain_name $1`
    # MySQL userid cannot be more than 15 characters long
    userid="${userid:0:15}"
    passwd=`get_password "$userid@mysql"`
    #Set up the wordpress config file with the mySQL database details
    cp wp-config-sample.php wp-config.php
    chmod 640 wp-config.php
    sed -i "s/database_name_here/$dbname/; s/username_here/$userid/; s/password_here/$passwd/" wp-config.php
    mysqladmin create "$dbname"
    echo "GRANT ALL PRIVILEGES ON \`$dbname\`.* TO \`$userid\`@localhost IDENTIFIED BY '$passwd';" | \
        mysql
    echo "FLUSH PRIVILEGES;"| \
        mysql
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
    cd /var/www/html

    # Setting up Nginx mapping
    
    #These variables are set for facilitating the writing of the site configuration file
    #It was the only way I could get it to work
    urivar='$uri'
    requri='$request_uri'
    argsvar='$args'
    docrootvar='$document_root'
    fastcgivar='$fastcgi_script_name'
    httpuseragent='$http_user_agent'
    #Create the server block config file - it tells the server where the root directory is for the site
    #Note: this setup establishes the site as www.site.com and not site.com. If you want the other way then
    #you need to swap the two server names around
    cat > /etc/nginx/sites-available/$1 << EOF
server {
    server_name $1;
    return       301 http://www.$1$requri;
}
server {
    listen 80 default_server;
    listen [::]:80 default_server ipv6only=on;

    root /var/www/html/$1/public_html/;
    index index.php index.html index.htm;

    server_name www.$1;

    location / {
        try_files $urivar $urivar/ /index.php?q=$urivar&$argsvar;
    }

    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/www;
    }

    location ~ \.php$ {
        try_files $urivar =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php7.0-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $docrootvar$fastcgivar;
        include fastcgi_params;
    }
	
	if ($httpuseragent ~* (rogerbot|exabot|gigabot|sitebot|AhrefsBot|mj12bot|dobot|spbot) ) {
		return 403;
	}
}
EOF
    #Enable the new server block
    sudo ln -s /etc/nginx/sites-available/$1 /etc/nginx/sites-enabled/
    #Restart the nginx service
    sudo service nginx restart
	#Restart the php7.0-fpm service
    sudo service php7.0-fpm restart
}

function install_exim4 {
    check_install mail exim4
    if [ -f /etc/exim4/update-exim4.conf.conf ]
    then
        sed -i \
            "s/dc_eximconfig_configtype='local'/dc_eximconfig_configtype='internet'/" \
            /etc/exim4/update-exim4.conf.conf
        invoke-rc.d exim4 restart
    fi
}

function install_php {
    sudo apt-get -q -y install php-fpm
    sudo apt-get -q -y install php-gd php-curl php-mysql php-ssh2 php-mbstring php-mcrypt php-xml php-xmlrpc
    sudo service php7.0-fpm restart
}

########################################################################
# START OF PROGRAM
########################################################################
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
case "$1" in
system)
    remove_unneeded
    update_upgrade
#    install_dash
#    install_syslogd
#    install_dropbear
#    install_exim4
    install_mysql
    install_nginx
    install_php
    ;;
wordpress)
    install_wordpress $2
    ;;
*)
    echo 'Usage:' `basename $0` '[option]'
    echo 'Available option:'
    for option in system wordpress
    do
        echo '  -' $option
    done
    ;;
esac




