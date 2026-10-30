#!/usr/bin/env bash
# =============================================================================
# Anonymous India — Nginx Setup Helper
# Copies nginx config & optionally gets Let's Encrypt SSL certificate
#
# Usage:
#   sudo bash scripts/setup-nginx.sh                      # HTTP only (IP-based)
#   sudo bash scripts/setup-nginx.sh api.yourdomain.com   # HTTP + request SSL
# =============================================================================
set -euo pipefail

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${COLOR_GREEN}[NGINX]${NC} $1"; }
warn() { echo -e "${COLOR_YELLOW}[WARN]${NC} $1"; }

[[ $EUID -ne 0 ]] && echo "Run as root: sudo bash $0 [domain]" && exit 1

DOMAIN="${1:-_}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_SRC="${SCRIPT_DIR}/../nginx/anonymous-backend.conf"
NGINX_DEST="/etc/nginx/sites-available/anonymous-backend"

# Install config
cp "${NGINX_SRC}" "${NGINX_DEST}"

# Replace placeholder domain
if [ "${DOMAIN}" != "_" ]; then
  sed -i "s/server_name _;/server_name ${DOMAIN};/" "${NGINX_DEST}"
  log "Domain set to: ${DOMAIN}"
fi

# Enable site
ln -sf "${NGINX_DEST}" /etc/nginx/sites-enabled/anonymous-backend
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Test and reload
nginx -t
systemctl reload nginx
log "Nginx configured and reloaded"

# SSL
if [ "${DOMAIN}" != "_" ]; then
  EMAIL="${SSL_EMAIL:-admin@anonymousindia.app}"
  log "Requesting Let's Encrypt SSL for ${DOMAIN} (email: ${EMAIL})..."
  certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}" --redirect
  log "SSL certificate installed"
  warn "Auto-renewal is handled by certbot systemd timer (certbot.timer)"
  systemctl enable certbot.timer || true
else
  warn "No domain provided — running HTTP only (fine for IP-based testing)"
fi

log "Done. Test: curl http://${DOMAIN}/api/health"
