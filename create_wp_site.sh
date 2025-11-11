#!/bin/bash
# Usage: sudo ./create_wp_site.sh dev.example.com example.com subfolder
# e.g., sudo ./create_wp_site.sh dev.example.com example.com client1
set -e

DEV_DOMAIN=$1       # WordPress dev subdomain
LIVE_DOMAIN=$2      # Live static domain
SUBFOLDER=$3        # Folder under /home/bitnami/sites/
DEV_ROOT="/home/bitnami/sites/$SUBFOLDER/public_html"
STATIC_ROOT="$DEV_ROOT/static"
DB_NAME="wp_${SUBFOLDER}"
DB_USER="wp_${SUBFOLDER}"
DB_PASS=$(openssl rand -base64 16)
APACHE_DEV_CONF="/etc/apache2/sites-available/${SUBFOLDER}-dev.conf"
APACHE_LIVE_CONF="/etc/apache2/sites-available/${SUBFOLDER}-live.conf"
GITHUB_REPO="git@github.com:buildingblocks-web/$SUBFOLDER.git"
SSH_KEY="/home/bitnami/.ssh/github_keys/id_ed25519_github"

# Validate input
if [ -z "$DEV_DOMAIN" ] || [ -z "$LIVE_DOMAIN" ] || [ -z "$SUBFOLDER" ]; then
    echo "Usage: sudo $0 dev.example.com example.com subfolder"
    exit 1
fi

echo "✅ Creating necessary folders..."
LOGS_DIR="/home/bitnami/sites/$SUBFOLDER/logs"

sudo mkdir -p $STATIC_ROOT $LOGS_DIR
sudo chown -R bitnami:www-data /home/bitnami/sites/$SUBFOLDER
sudo chmod -R 755 /home/bitnami/sites/$SUBFOLDER

echo "✅ Cloning WordPress from GitHub..."
DEV_ROOT="/home/bitnami/sites/$SUBFOLDER/public_html"
mkdir -p "$DEV_ROOT"

rm -rf /home/bitnami/sites/buildingblocks/public_html/*
# Clone or pull safely
if [ -d "$DEV_ROOT/.git" ]; then
    echo "✅ Repository exists, pulling latest changes..."
    GIT_SSH_COMMAND="ssh -i $SSH_KEY" git -C "$DEV_ROOT" pull || { echo "❌ Git pull failed! Exiting."; exit 1; }
else
    # Check if folder is empty
    if [ "$(ls -A "$DEV_ROOT")" ]; then
        echo "❌ $DEV_ROOT is not empty. Please empty it manually or choose another folder."
        exit 1
    fi
    echo "✅ Cloning repository into $DEV_ROOT..."
    GIT_SSH_COMMAND="ssh -i $SSH_KEY" git clone "$GITHUB_REPO" "$DEV_ROOT" || { echo "❌ Git clone failed! Exiting."; exit 1; }
fi

echo "✅ Updating wp-config.php with database credentials..."
WP_CONFIG="$DEV_ROOT/wp-config.php"
sed -i "s/database_name_here/${DB_NAME}/" "$WP_CONFIG"
sed -i "s/username_here/${DB_USER}/" "$WP_CONFIG"
sed -i "s/password_here/${DB_PASS}/" "$WP_CONFIG"

echo "✅ Creating MySQL database..."
sudo mysql -e "CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "✅ Creating Apache VirtualHosts..."

# Dev site (WordPress)
sudo tee $APACHE_DEV_CONF > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $DEV_DOMAIN
    DocumentRoot $DEV_ROOT

    <Directory $DEV_ROOT>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /home/bitnami/sites/$SUBFOLDER/logs/dev-error.log
    CustomLog /home/bitnami/sites/$SUBFOLDER/logs/dev-access.log combined
</VirtualHost>
EOF

# Live site (Static)
sudo tee $APACHE_LIVE_CONF > /dev/null <<EOF
<VirtualHost *:80>
    ServerName $LIVE_DOMAIN
    DocumentRoot $STATIC_ROOT

    <Directory $STATIC_ROOT>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /home/bitnami/sites/$SUBFOLDER/logs/static-error.log
    CustomLog /home/bitnami/sites/$SUBFOLDER/logs/static-access.log combined
</VirtualHost>
EOF

echo "✅ Enabling Apache sites and reloading..."
sudo a2ensite ${SUBFOLDER}-dev.conf
sudo a2ensite ${SUBFOLDER}-live.conf
sudo systemctl reload apache2 || sudo systemctl restart apache2

echo "✅ Done!"
echo "WordPress dev site created at: $DEV_ROOT (visit http://$DEV_DOMAIN to finish setup)"
echo "Live static site created at: $STATIC_ROOT (visit http://$LIVE_DOMAIN)"
echo "Database: $DB_NAME"
echo "DB User: $DB_USER"
echo "DB Password: $DB_PASS"
