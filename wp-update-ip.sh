#!/usr/bin/env bash
# wp-update-ip.sh
# Updates WordPress 'siteurl' and 'home' in the database to this machine's current IP.
#
# Usage:
#   ./wp-update-ip.sh                 # auto-detect IP, WordPress in /var/www/html
#   ./wp-update-ip.sh -p /path/to/wp  # custom WordPress path
#   ./wp-update-ip.sh -i 192.168.1.50 # force a specific IP
#   ./wp-update-ip.sh -s              # use https instead of http

set -euo pipefail

WP_PATH="/var/www/html"
FORCED_IP=""
SCHEME="http"

while getopts "p:i:sh" opt; do
  case "$opt" in
    p) WP_PATH="$OPTARG" ;;
    i) FORCED_IP="$OPTARG" ;;
    s) SCHEME="https" ;;
    h|*) sed -n '2,10p' "$0"; exit 0 ;;
  esac
done

CONFIG="$WP_PATH/wp-config.php"
[[ -f "$CONFIG" ]] || { echo "ERROR: $CONFIG not found. Use -p to set the WordPress path." >&2; exit 1; }

# --- Detect current IP ---
if [[ -n "$FORCED_IP" ]]; then
  IP="$FORCED_IP"
else
  IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')"
  [[ -n "$IP" ]] || IP="$(hostname -I | awk '{print $1}')"
fi

[[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "ERROR: could not determine a valid IPv4 address (got '$IP')." >&2; exit 1; }

NEW_URL="$SCHEME://$IP"

# --- Read DB name and table prefix from wp-config.php ---
DB_NAME="$(grep -E "define\(\s*'DB_NAME'" "$CONFIG" | sed -E "s/.*'DB_NAME'\s*,\s*'([^']*)'.*/\1/")"
PREFIX="$(grep -E '^\s*\$table_prefix' "$CONFIG" | sed -E "s/.*=\s*'([^']*)'.*/\1/")"

[[ -n "$DB_NAME" ]] || { echo "ERROR: could not read DB_NAME from wp-config.php." >&2; exit 1; }
[[ -n "$PREFIX" ]] || PREFIX="wp_"
[[ "$PREFIX" =~ ^[A-Za-z0-9_]+$ ]] || { echo "ERROR: unexpected table prefix '$PREFIX'." >&2; exit 1; }

TABLE="${PREFIX}options"

# --- Show current values ---
echo "Database : $DB_NAME"
echo "Table    : $TABLE"
echo "New URL  : $NEW_URL"
echo
echo "Current values:"
sudo mysql -D "$DB_NAME" -e "SELECT option_name, option_value FROM \`$TABLE\` WHERE option_name IN ('siteurl','home');"

# --- Update ---
sudo mysql -D "$DB_NAME" -e "UPDATE \`$TABLE\` SET option_value='$NEW_URL' WHERE option_name IN ('siteurl','home');"

echo
echo "Updated values:"
sudo mysql -D "$DB_NAME" -e "SELECT option_name, option_value FROM \`$TABLE\` WHERE option_name IN ('siteurl','home');"

echo
echo "Done. Reload the site with Ctrl+Shift+R: $NEW_URL/wp-admin/"
