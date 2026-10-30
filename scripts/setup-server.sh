#!/usr/bin/env bash
# =============================================================================
# Anonymous India — Ubuntu EC2 Server Setup
# One-time run on a fresh Ubuntu 22.04 / 24.04 t2.micro (1 GB RAM)
#
# Usage:
#   chmod +x scripts/setup-server.sh
#   sudo bash scripts/setup-server.sh
# =============================================================================
set -euo pipefail

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${COLOR_GREEN}[SETUP]${NC} $1"; }
warn() { echo -e "${COLOR_YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${COLOR_RED}[ERROR]${NC} $1"; exit 1; }

[[ $EUID -ne 0 ]] && die "Run as root: sudo bash $0"

APP_USER="${APP_USER:-ubuntu}"
APP_DIR="/home/${APP_USER}/anonymous-backend"
REPO_URL="${REPO_URL:-https://github.com/DeepBoda/anonymous-backend.git}"

# =============================================================================
# 1. SWAP FILE (critical for 1 GB RAM — prevents OOM during npm install/build)
# =============================================================================
log "Setting up 1 GB swap file..."
if [ ! -f /swapfile ]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl vm.swappiness=10
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  log "Swap created (1 GB)"
else
  warn "Swap already exists, skipping"
fi

# =============================================================================
# 2. SYSTEM PACKAGES
# =============================================================================
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  curl wget git build-essential \
  nginx certbot python3-certbot-nginx \
  ufw \
  htop vim \
  postgresql-client \
  --no-install-recommends

# =============================================================================
# 3. NODE.JS 20 via NVM (install per-user, not system-wide)
# =============================================================================
log "Installing Node.js 20 via NVM for user ${APP_USER}..."
sudo -u "${APP_USER}" bash <<'NODEEOF'
  export NVM_DIR="$HOME/.nvm"
  if [ ! -d "$NVM_DIR" ]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  source "$NVM_DIR/nvm.sh"
  nvm install 20
  nvm alias default 20
  nvm use default
  echo "Node $(node --version), npm $(npm --version)"
  # Record the bin dir so root can symlink it below (this block runs as ${APP_USER}
  # and therefore cannot write to /usr/local/bin itself).
  dirname "$(nvm which default)" > /tmp/node_bin_dir
NODEEOF

# Symlink node/npm/npx system-wide AS ROOT so later steps (pm2) and any shell find them.
NODE_DIR="$(cat /tmp/node_bin_dir)"
[[ -x "${NODE_DIR}/node" ]] || die "Node install failed — ${NODE_DIR}/node not found"
for bin in node npm npx; do
  ln -sf "${NODE_DIR}/${bin}" "/usr/local/bin/${bin}"
done
rm -f /tmp/node_bin_dir
log "Node available system-wide: $(node --version), npm $(npm --version)"

# =============================================================================
# 4. PM2
# =============================================================================
log "Installing PM2..."
npm install -g pm2@latest
ln -sf "$(dirname "$(readlink -f /usr/local/bin/node)")/pm2" /usr/local/bin/pm2 2>/dev/null || true
pm2 startup systemd -u "${APP_USER}" --hp "/home/${APP_USER}" | tail -1 | bash || true
log "PM2 installed: $(pm2 --version)"

# =============================================================================
# 5. REDIS (same instance to avoid network cost — ok for 1GB with swap)
# =============================================================================
log "Installing Redis..."
apt-get install -y redis-server
# Tune Redis for low memory
sed -i 's/^# maxmemory .*/maxmemory 128mb/'           /etc/redis/redis.conf
sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
sed -i 's/^appendonly yes/appendonly no/'              /etc/redis/redis.conf  || true
# Bind to localhost only
sed -i 's/^bind .*/bind 127.0.0.1 ::1/'               /etc/redis/redis.conf
systemctl enable redis-server
systemctl restart redis-server
log "Redis running: $(redis-cli ping)"

# =============================================================================
# 6. LOG DIRECTORY
# =============================================================================
log "Creating log directory..."
mkdir -p /var/log/anonymous
chown -R "${APP_USER}:${APP_USER}" /var/log/anonymous

# =============================================================================
# 7. CLONE / PULL REPO
# =============================================================================
log "Setting up application directory..."
if [ ! -d "${APP_DIR}" ]; then
  sudo -u "${APP_USER}" git clone "${REPO_URL}" "${APP_DIR}"
else
  warn "Repo already cloned at ${APP_DIR}"
fi

# =============================================================================
# 8. UFW FIREWALL
# =============================================================================
log "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
# Port 3001 is NOT exposed publicly — nginx proxies it
ufw --force enable
log "UFW status: $(ufw status | head -1)"

# =============================================================================
# 9. NGINX — will be fully configured by setup-nginx.sh
# =============================================================================
log "Enabling nginx..."
systemctl enable nginx
systemctl start nginx

# =============================================================================
# DONE
# =============================================================================
echo ""
echo -e "${COLOR_GREEN}=============================================${NC}"
echo -e "${COLOR_GREEN}  Server setup complete!${NC}"
echo -e "${COLOR_GREEN}=============================================${NC}"
echo ""
echo "NEXT STEPS:"
echo "  1. cd ${APP_DIR}"
echo "  2. cp .env.production.example .env && nano .env   # fill in secrets"
echo "  3. bash scripts/setup-nginx.sh yourdomain.com     # configure nginx"
echo "  4. bash scripts/deploy.sh                         # first deploy"
echo ""
