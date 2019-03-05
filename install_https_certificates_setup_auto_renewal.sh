# Install the certificates for all the domains on the server
sudo certbot --apache -d $1 -d www.$1 -d $2 -d www.$2 -d $3 -d www.$3
# Setup cronjob for automatic renewal 
(crontab -l ; echo "30 2 */2 * * /usr/bin/certbot renew >> /var/log/letsencrypt/renew.log")| crontab -
