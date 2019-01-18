#!/bin/bash

function check_sanity {
    # Do some sanity checking.
    if [ $(/usr/bin/id -u) != "0" ]
    then
        die 'Must be run by root user'
    fi
}

function housekeeping {
    # Stop and remove Apache2 first. Then bind and sendmail. Then update
	# This should be done before we try to install any package
	sudo service apache2 stop
	sudo apt-get purge apache2 apache2-utils apache2.2-bin apache2-common
	sudo apt-get autoremove
	sudo rm -rf /etc/apache2
	apt-get remove -y bind9
	invoke-rc.d sendmail stop
	apt-get purge sendmail*
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
            apt-get -q -y install "$1"
            print_info "$1 installed for $executable"
            shift
        done
    else
        print_warn "$2 already installed"
    fi
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
        apt-get -q -y remove --purge "$2"
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
    check_install mysqld mysql-server
    check_install mysql mysql-client

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

function install_php {
    sudo apt-get -q -y install php-fpm
    check_install php-gd php-curl php-mysql libssh2-php
    sudo apt-get install -q -y php-gd
    sudo service php7.0-fpm restart
}

########################################################################
# START OF PROGRAM
########################################################################
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
case "$1" in
system)
    housekeeping
    install_dash
    install_syslogd
    install_dropbear
    install_exim4
    install_mysql
    install_nginx
    install_php
    ;;
*)
    echo 'Usage:' `basename $0` '[option]'
    echo 'Available option:'
    for option in system exim4 mysql nginx php wordpress
    do
        echo '  -' $option
    done
    ;;
esac
