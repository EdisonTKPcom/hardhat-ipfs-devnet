# Hardhat IPFS DevNet

A comprehensive one-script setup for a combined Ethereum development network (Hardhat) and IPFS node with SSL/TLS termination via Nginx reverse proxy. Perfect for Web3 development environments that need both blockchain functionality and decentralized storage.

## 🚀 What This Does

This repository provides a single bash script that automatically sets up:

- **Hardhat Development Network**: Local Ethereum blockchain for smart contract development
- **IPFS Node (Kubo)**: InterPlanetary File System for decentralized storage
- **Nginx Reverse Proxy**: SSL/TLS termination and routing for both services
- **PM2 Process Management**: Automatic restart and monitoring of services
- **Let's Encrypt SSL**: Free SSL certificates with automatic renewal
- **Firewall Configuration**: Secure UFW setup

## 🏗️ Architecture

```
Internet → Nginx (SSL/TLS) → Services
                    ├── /rpc → Hardhat JSON-RPC (127.0.0.1:8545)
                    ├── /ipfs → IPFS Gateway (127.0.0.1:8080)
                    ├── /ipns → IPFS Gateway (127.0.0.1:8080)
                    └── /healthz → Health check endpoint
```

**Services:**
- Hardhat JSON-RPC API: `https://yourdomain.com/rpc`
- IPFS Gateway: `https://yourdomain.com/ipfs/{hash}`
- IPFS IPNS: `https://yourdomain.com/ipns/{name}`
- IPFS API (local only): `127.0.0.1:5001` (not exposed publicly)

## 📋 Prerequisites

- **Ubuntu/Debian Server** (20.04+ recommended)
- **Root Access** (`sudo -i`)
- **Domain Name** with DNS A record pointing to your server IP
- **Open Ports**: 22 (SSH), 80 (HTTP), 443 (HTTPS)

## ⚡ Quick Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/EdisonTKPcom/hardhat-ipfs-devnet.git
   cd hardhat-ipfs-devnet
   ```

2. **Configure the script** (edit these variables at the top of `setup-devnet.sh`):
   ```bash
   DOMAIN="your-domain.com"              # Your domain name
   EMAIL="admin@your-domain.com"         # Email for Let's Encrypt
   HARDHAT_DIR="/opt/hardhat-devnet"     # Hardhat installation directory
   NODE_MAJOR="20"                       # Node.js version (20 or 22)
   KUBO_TAG="latest"                     # IPFS Kubo version
   ```

3. **Run the setup script:**
   ```bash
   sudo -i
   bash setup-devnet.sh
   ```

4. **Wait for completion** (5-10 minutes depending on server specs)

## 🔧 Configuration

### Domain Configuration
Before running the script, ensure:
- Your domain's DNS A record points to your server's IP address
- The domain is accessible from the internet (for Let's Encrypt validation)

### Customizable Variables
Edit the top of `setup-devnet.sh` to customize:

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN` | Your domain name | `devnet.edisontkp.com` |
| `EMAIL` | Email for Let's Encrypt notifications | `admin@devnet.edisontkp.com` |
| `HARDHAT_DIR` | Hardhat installation directory | `/opt/hardhat-devnet` |
| `NODE_MAJOR` | Node.js major version | `20` |
| `KUBO_TAG` | IPFS Kubo version | `latest` |

## 📡 API Usage

### Hardhat JSON-RPC

Connect your Web3 applications to the Hardhat network:

```javascript
// Web3.js
const Web3 = require('web3');
const web3 = new Web3('https://your-domain.com/rpc');

// Ethers.js
const { ethers } = require('ethers');
const provider = new ethers.providers.JsonRpcProvider('https://your-domain.com/rpc');

// Network Details
// Chain ID: 31337 (Hardhat default)
// Accounts: 20 pre-funded accounts available
```

### IPFS Gateway

Access IPFS content through your domain:

```bash
# Upload file to IPFS (via local API)
curl -X POST -F file=@example.txt http://127.0.0.1:5001/api/v0/add

# Access via your gateway
curl https://your-domain.com/ipfs/QmYourHashHere

# Access IPNS content
curl https://your-domain.com/ipns/your-ipns-name
```

### Health Check

```bash
curl https://your-domain.com/healthz
# Returns: ok
```

## 🛠️ Management Commands

### PM2 Process Management

```bash
# Check status
pm2 status

# View logs
pm2 logs ipfs
pm2 logs hardhat-devnet

# Restart services
pm2 restart ipfs
pm2 restart hardhat-devnet

# Stop services
pm2 stop ipfs
pm2 stop hardhat-devnet
```

### Nginx Management

```bash
# Check status
systemctl status nginx

# Reload configuration
systemctl reload nginx

# Test configuration
nginx -t
```

### SSL Certificate Management

```bash
# Check certificate status
certbot certificates

# Renew certificates (automatic via cron)
certbot renew

# Manual renewal
certbot --nginx -d your-domain.com
```

## 🐛 Troubleshooting

### Service Issues

1. **Check PM2 processes:**
   ```bash
   pm2 status
   pm2 logs ipfs
   pm2 logs hardhat-devnet
   ```

2. **Restart failed services:**
   ```bash
   pm2 restart ipfs
   pm2 restart hardhat-devnet
   ```

### Network Issues

1. **Check firewall status:**
   ```bash
   ufw status
   ```

2. **Check nginx configuration:**
   ```bash
   nginx -t
   systemctl status nginx
   ```

3. **Check SSL certificate:**
   ```bash
   certbot certificates
   ```

### IPFS Issues

1. **Check IPFS daemon:**
   ```bash
   pm2 logs ipfs
   ```

2. **Test local IPFS API:**
   ```bash
   curl http://127.0.0.1:5001/api/v0/version
   ```

### Hardhat Issues

1. **Check Hardhat logs:**
   ```bash
   pm2 logs hardhat-devnet
   ```

2. **Test JSON-RPC locally:**
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     http://127.0.0.1:8545
   ```

## 🔒 Security Considerations

- **IPFS API** is only accessible locally (`127.0.0.1:5001`) - not exposed publicly
- **UFW Firewall** configured to allow only SSH, HTTP, and HTTPS
- **SSL/TLS** encryption for all public endpoints
- **CORS** headers configured for development (update for production)

## 📁 File Locations

| Service | Configuration | Logs |
|---------|---------------|------|
| Nginx | `/etc/nginx/sites-available/your-domain.com` | `/var/log/nginx/` |
| IPFS | `/root/.ipfs/config` | `pm2 logs ipfs` |
| Hardhat | `/opt/hardhat-devnet/hardhat.config.js` | `pm2 logs hardhat-devnet` |
| SSL Certs | `/etc/letsencrypt/live/your-domain.com/` | `/var/log/letsencrypt/` |

## 🔄 What the Script Does

1. **System Updates**: Updates packages and installs dependencies
2. **Node.js Setup**: Installs Node.js LTS and PM2 process manager
3. **Firewall**: Configures UFW for SSH and web traffic
4. **IPFS Installation**: Downloads and installs Kubo (IPFS implementation)
5. **IPFS Configuration**: Sets up IPFS daemon with proper endpoints
6. **PM2 IPFS**: Runs IPFS daemon as PM2 managed process
7. **Hardhat Setup**: Creates Hardhat project with basic configuration
8. **PM2 Hardhat**: Runs Hardhat node as PM2 managed process
9. **PM2 Persistence**: Configures PM2 to start on boot
10. **Nginx Configuration**: Sets up reverse proxy for both services
11. **SSL Setup**: Issues Let's Encrypt certificates
12. **Health Checks**: Verifies all services are running

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🆘 Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check the troubleshooting section above
- Review the setup script logs for detailed error messages