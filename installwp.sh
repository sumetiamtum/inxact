#!/bin/bash

function install_wordpress {
    check_install wget wget
    if [ -z "$1" ]
    then
        die "Usage: `basename $0` wordpress <hostname>"
    fi

    #Create the necessary folder structure
    sudo mkdir -p /var/www/html/$1/{public_html,private,logs,cgi-bin,backup}
    #We should change the ownership of this directory
    sudo chown -R $USER:$USER /var/www/html/$1/public_html/
    #Set the read permissions to the Nginx web root (/var/www/html/) directory, so that everyone can read files from that directory.
    sudo chmod -R 755 /var/www/html/
    #Downloading the WordPress' latest and greatest distribution.
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
    listen 80 default_server;
    listen [::]:80 default_server
    root /var/www/html/$1/public_html/;
    index index.php index.html index.htm;
    server_name $1 www.$1;
    
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
        fastcgi_pass unix:/run/php/php7.0-fpm.sock;
		include fastcgi_params;
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

install_wordpress $1
