#!/usr/bin/env bash
set -euo pipefail

### ====== CONFIG (edit these) ======
DOMAIN="devnet.edisontkp.com"
EMAIL="admin@devnet.edisontkp.com"     # for Let's Encrypt registration & renewal notices
HARDHAT_DIR="/opt/hardhat-devnet"  # where the devnet project will live
NODE_MAJOR="20"                    # Node LTS major (20 or 22 are common)
# KUBO_TAG: set to "latest" to auto-resolve from GitHub API, or pin like "v0.28.0"
KUBO_TAG="latest"
### =================================

export DEBIAN_FRONTEND=noninteractive

log() { echo -e "\n[$(date +'%F %T')] $*"; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as root (sudo -i)"; exit 1
  fi
}

detect_arch() {
  local arch="$(uname -m)"
  case "$arch" in
    x86_64)  echo "linux-amd64" ;;
    aarch64) echo "linux-arm64" ;;
    arm64)   echo "linux-arm64" ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
  esac
}

resolve_kubo_tag() {
  # If pinned, return it
  if [[ "$KUBO_TAG" != "latest" ]]; then
    echo "$KUBO_TAG"; return 0
  fi
  # Try GitHub API
  if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local tag
    tag="$(curl -fsSL --max-time 10 https://api.github.com/repos/ipfs/kubo/releases/latest | jq -r .tag_name || true)"
    if [[ -n "${tag:-}" && "$tag" != "null" ]]; then
      echo "$tag"; return 0
    fi
  fi
  # Fallback to a known-good version if API fails
  echo "v0.28.0"
}

ensure_packages() {
  log "[1/12] System update & base packages"
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y \
    nginx \
    python3-certbot-nginx \
    ufw \
    curl \
    ca-certificates \
    gnupg \
    git \
    jq \
    unzip
}

install_node_pm2() {
  log "[2/12] Node.js ${NODE_MAJOR}.x & PM2"
  if ! command -v node >/dev/null 2>&1 || [[ "$(node -v | tr -d 'v' | cut -d. -f1)" -ne "${NODE_MAJOR}" ]]; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
    apt-get install -y nodejs
  fi
  npm install -g pm2@latest
}

configure_firewall() {
  log "[3/12] UFW allow SSH + Nginx (non-interactive)"
  ufw allow OpenSSH || true
  ufw allow 'Nginx Full' || true
  if ufw status | grep -q "inactive"; then
    echo "y" | ufw enable || true
  fi
}

install_kubo() {
  log "[4/12] Install Kubo (IPFS) from dist.ipfs.tech"
  local arch kubo_tag tgz url tmp_tgz
  arch="$(detect_arch)"
  kubo_tag="$(resolve_kubo_tag)"
  tgz="kubo_${kubo_tag}_${arch}.tar.gz"
  url="https://dist.ipfs.tech/kubo/${kubo_tag}/${tgz}"
  tmp_tgz="/tmp/${tgz}"

  # Skip if already installed
  if command -v ipfs >/dev/null 2>&1; then
    log "Kubo already installed: $(ipfs --version)"
  else
    log "Downloading ${url}"
    curl -fL "${url}" -o "${tmp_tgz}"

    log "Extract & install"
    (cd /tmp && tar -xzf "${tmp_tgz}")
    (cd /tmp/kubo && bash install.sh)

    log "Installed: $(ipfs --version)"
  fi

  # Initialize repo if not present
  if [[ ! -d "/root/.ipfs" ]]; then
    log "Initialize IPFS repo"
    ipfs init --profile server
    ipfs config --json Addresses.API '"/ip4/127.0.0.1/tcp/5001"'
    ipfs config --json Addresses.Gateway '"/ip4/127.0.0.1/tcp/8080"'
    # Optional public gateway hints for your domain (works with Nginx reverse proxy)
    ipfs config --json Gateway.PublicGateways "{
      \"${DOMAIN}\": {
        \"Paths\": [\"/ipfs\", \"/ipns\"],
        \"UseSubdomains\": false,
        \"InlineDNSLink\": true
      }
    }" || true
  fi
}

pm2_ipfs() {
  log "[5/12] PM2 process for IPFS daemon"
  if pm2 list | grep -qE '^\s*ipfs\s'; then
    pm2 delete ipfs || true
  fi
  pm2 start "ipfs daemon --enable-gc" --name ipfs --time --restart-delay=2000
}

setup_hardhat() {
  log "[6/12] Hardhat devnet project & PM2 process"
  mkdir -p "$HARDHAT_DIR"
  cd "$HARDHAT_DIR"

  if [[ ! -f "package.json" ]]; then
    npm init -y
    npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
    cat > hardhat.config.js <<'EOF'
/** Minimal Hardhat config for local devnet */
require("@nomicfoundation/hardhat-toolbox");
module.exports = {
  solidity: "0.8.24",
  networks: {
    hardhat: {
      chainId: 31337,
      accounts: { count: 20 }
    }
  }
};
EOF
  fi

  if pm2 list | grep -qE '^\s*hardhat-devnet\s'; then
    pm2 delete hardhat-devnet || true
  fi

  pm2 start "npx hardhat node --hostname 127.0.0.1 --port 8545" \
    --name hardhat-devnet --time --restart-delay=2000
}

pm2_boot() {
  log "[7/12] PM2 startup & save"
  pm2 startup systemd -u root --hp /root >/dev/null
  pm2 save
}

nginx_site() {
  log "[8/12] Nginx site for ${DOMAIN}"
  local site="/etc/nginx/sites-available/${DOMAIN}"
  cat > "$site" <<EOF
# Reverse proxy for Hardhat JSON-RPC and IPFS Gateway
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    client_max_body_size 100m;

    # --- Hardhat JSON-RPC on /rpc ---
    location /rpc {
        proxy_pass http://127.0.0.1:8545/;
        proxy_http_version 1.1;
        proxy_set_header Connection "keep-alive";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        # Dev CORS
        add_header Access-Control-Allow-Origin "*";
        add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type, Authorization";
        if (\$request_method = OPTIONS) { return 204; }
    }

    # --- IPFS Gateway on /ipfs and /ipns ---
    location /ipfs {
        proxy_pass http://127.0.0.1:8080/ipfs;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location /ipns {
        proxy_pass http://127.0.0.1:8080/ipns;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Health
    location /healthz {
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
EOF

  ln -sf "$site" "/etc/nginx/sites-enabled/${DOMAIN}"
  [[ -e /etc/nginx/sites-enabled/default ]] && rm -f /etc/nginx/sites-enabled/default

  nginx -t
  systemctl reload nginx
}

letsencrypt() {
  log "[9/12] Issue/renew Let's Encrypt cert for ${DOMAIN}"
  # This will also create HTTPS server block + 80->443 redirect
  certbot --nginx -d "$DOMAIN" --email "$EMAIL" --non-interactive --agree-tos --redirect
}

post_checks() {
  log "[10/12] Status & summary"
  systemctl status nginx --no-pager || true
  pm2 status || true

  cat <<INFO

=========================================================
SUCCESS!

Services:
- Hardhat JSON-RPC (local): 127.0.0.1:8545  (proxied at https://${DOMAIN}/rpc)
- IPFS Gateway (local):     127.0.0.1:8080  (proxied at https://${DOMAIN}/ipfs and /ipns)
- IPFS API (local only):    127.0.0.1:5001  (NOT exposed publicly)

PM2:
- Apps: ipfs, hardhat-devnet
  View logs:     pm2 logs ipfs     | pm2 logs hardhat-devnet
  Restart apps:  pm2 restart ipfs  | pm2 restart hardhat-devnet
  Persist:       pm2 save (done), boots via systemd (done)

Nginx:
- Config: /etc/nginx/sites-available/${DOMAIN}
- Quick test: curl -I https://${DOMAIN}/healthz

Certs:
- Auto-renew via certbot timers (twice daily)

Notes:
- Ensure DNS A record for ${DOMAIN} → this droplet's IP before running certbot.
- To expose IPFS API publicly (NOT recommended), proxy /api/v0 to 127.0.0.1:5001 and add auth/rate limits.
=========================================================
INFO
}

main() {
  require_root
  ensure_packages
  install_node_pm2
  configure_firewall
  install_kubo
  pm2_ipfs
  setup_hardhat
  pm2_boot
  nginx_site
  letsencrypt
  post_checks
}

main "$@"
