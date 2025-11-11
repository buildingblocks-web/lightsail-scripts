#!/bin/bash
# Usage: ./create_wp_site.sh dev.example.com example.com subfolder
# Example: ./create_wp_site.sh dev.buildingblocksweb.com buildingblocksweb.com buildingblocks

set -e

DEV_DOMAIN=$1
LIVE_DOMAIN=$2
SUBFOLDER=$3

DEV_ROOT="/home/bitnami/sites/$SUBFOLDER/public_html"
STATIC_ROOT="$DEV_ROOT/static"
LOGS_DIR="/home/bitnami/sites/$SUBFOLDER/logs"

DB_NAME="wp_${SUBFOLDER}"
DB_USER="wp_${SUBFOLDER}"
DB_PASS=$(openssl rand -base64 16)

APACHE_DEV_CONF="/opt/bitnami/apache2/conf/vhosts/${SUBFOLDER}-dev.conf"
APACHE_LIVE_CONF="/opt/bitnami/apache2/conf/vhosts/${SUBFOLDER}-live.conf"

GITHUB_REPO="git@github.com:buildingblocks-web/$SUBFOLDER.git"
SSH_KEY="/home/bitnami/.ssh/github_keys/id_ed25519_github"
MARIADB_BIN="/opt/bitnami/mariadb/bin/mariadb"
ROOT_PWD=$(cat /home/bitnami/bitnami_application_password)

# -------- Validate input ----------
if [ -z "$DEV_DOMAIN" ] || [ -z "$LIVE_DOMAIN" ] || [ -z "$SUBFOLDER" ]; then
    echo "Usage: $0 dev.example.com example.com subfolder"
    exit 1
fi

# -------- Create folders ----------
echo "✅ Creating necessary folders..."
sudo mkdir -p "$STATIC_ROOT" "$LOGS_DIR"
sudo chown -R bitnami:www-data "/home/bitnami/sites/$SUBFOLDER"
sudo chmod -R 755 "/home/bitnami/sites/$SUBFOLDER"

# -------- Git clone / pull ----------
echo "✅ Pulling repository from GitHub..."
mkdir -p "$DEV_ROOT"

if [ -d "$DEV_ROOT/.git" ]; then
    echo "Repository exists, pulling latest changes..."
    GIT_SSH_COMMAND="ssh -i $SSH_KEY" git -C "$DEV_ROOT" pull || { echo "❌ Git pull failed! Exiting."; exit 1; }
else
    if [ "$(ls -A "$DEV_ROOT")" ]; then
        echo "❌ $DEV_ROOT is not empty. Please empty it manually or choose another folder."
        exit 1
    fi
    echo "Cloning repository into $DEV_ROOT..."
    GIT_SSH_COMMAND="ssh -i $SSH_KEY" git clone "$GITHUB_REPO" "$DEV_ROOT" || { echo "❌ Git clone failed! Exiting."; exit 1; }
fi

# -------- Update wp-config.php ----------
WP_CONFIG="$DEV_ROOT/wp-config.php"
if [ -f "$WP_CONFIG" ]; then
    echo "✅ Updating wp-config.php with DB credentials..."
    sed -i "s/database_name_here/${DB_NAME}/" "$WP_CONFIG"
    sed -i "s/username_here/${DB_USER}/" "$WP_CONFIG"
    sed -i "s/password_here/${DB_PASS}/" "$WP_CONFIG"
fi

# -------- Create MariaDB database ----------
echo "✅ Creating MySQL database..."
sudo $MARIADB_BIN -u root -p"$ROOT_PWD" -e "CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || true
sudo $MARIADB_BIN -u root -p"$ROOT_PWD" -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" || true
sudo $MARIADB_BIN -u root -p"$ROOT_PWD" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo $MARIADB_BIN -u root -p"$ROOT_PWD" -e "FLUSH PRIVILEGES;"

# -------- Create Apache VirtualHosts ----------
echo "✅ Creating Apache VirtualHosts..."

# Dev site
sudo tee "$APACHE_DEV_CONF" > /dev/null <<EOF
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

# Live static site
sudo tee "$APACHE_LIVE_CONF" > /dev/null <<EOF
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

# -------- Enable Apache sites ----------
echo "✅ Enabling Apache sites and reloading..."
sudo a2ensite "${SUBFOLDER}-dev.conf"
sudo a2ensite "${SUBFOLDER}-live.conf"
sudo /opt/bitnami/ctlscript.sh reload apache

# -------- Done ----------
echo "✅ Done!"
echo "WordPress dev site created at: $DEV_ROOT (visit http://$DEV_DOMAIN to finish setup)"
echo "Live static site created at: $STATIC_ROOT (visit http://$LIVE_DOMAIN)"
echo "Database: $DB_NAME"
echo "DB User: $DB_USER"
echo "DB Password: $DB_PASS"
