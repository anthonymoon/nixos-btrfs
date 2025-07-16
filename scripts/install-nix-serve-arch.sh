#!/usr/bin/env bash
# Install and configure nix-serve on Arch Linux (CachyOS)

set -euo pipefail

echo "Installing nix-serve binary cache on Arch Linux"
echo "=============================================="

# Check if running on Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    echo "ERROR: This script is designed for Arch Linux systems"
    exit 1
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Do not run this script as root"
    exit 1
fi

# Install dependencies
echo "Installing dependencies..."
sudo pacman -S --needed nix nginx certbot-nginx

# Enable and start Nix daemon
echo "Enabling Nix daemon..."
sudo systemctl enable --now nix-daemon

# Add user to nix-users group
echo "Adding user to nix-users group..."
sudo usermod -aG nix-users $USER

# Install nix-serve
echo "Installing nix-serve..."
nix-env -iA nixpkgs.nix-serve

# Create nix-serve user and directories
echo "Creating nix-serve user and directories..."
sudo useradd -r -s /bin/false -d /var/lib/nix-serve nix-serve || true
sudo mkdir -p /var/lib/nix-serve /var/log/nix-serve
sudo chown nix-serve:nix-serve /var/lib/nix-serve /var/log/nix-serve

# Generate signing key for binary cache
echo "Generating signing key..."
sudo -u nix-serve nix-store --generate-binary-cache-key cachy.local /var/lib/nix-serve/cache-priv-key.pem /var/lib/nix-serve/cache-pub-key.pem

# Create systemd service for nix-serve
echo "Creating systemd service..."
sudo tee /etc/systemd/system/nix-serve.service > /dev/null << 'EOF'
[Unit]
Description=Nix binary cache server
After=network.target

[Service]
Type=simple
User=nix-serve
Group=nix-serve
WorkingDirectory=/var/lib/nix-serve
ExecStart=/home/amoon/.nix-profile/bin/nix-serve --listen 127.0.0.1:5000 --key /var/lib/nix-serve/cache-priv-key.pem
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create nginx configuration
echo "Creating nginx configuration..."
sudo tee /etc/nginx/sites-available/nix-serve > /dev/null << 'EOF'
server {
    listen 80;
    server_name cachy.local;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Enable compression
        gzip on;
        gzip_types application/x-nix-archive;
        
        # Cache static content
        location ~* \.(narinfo|nar)$ {
            expires 1h;
            add_header Cache-Control "public, immutable";
        }
    }
}
EOF

# Enable nginx site
sudo mkdir -p /etc/nginx/sites-enabled
sudo ln -sf /etc/nginx/sites-available/nix-serve /etc/nginx/sites-enabled/

# Update main nginx config to include sites-enabled
if ! grep -q "include /etc/nginx/sites-enabled" /etc/nginx/nginx.conf; then
    sudo sed -i '/http {/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
fi

# Start and enable services
echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable --now nix-serve
sudo systemctl enable --now nginx

# Display public key
echo ""
echo "Binary cache setup complete!"
echo "=============================="
echo ""
echo "Public key for binary cache:"
cat /var/lib/nix-serve/cache-pub-key.pem
echo ""
echo "Binary cache URL: http://cachy.local"
echo ""
echo "To use this cache, add to your NixOS configuration:"
echo "  nix.settings.substituters = [ \"http://cachy.local\" ];"
echo "  nix.settings.trusted-public-keys = [ \"$(cat /var/lib/nix-serve/cache-pub-key.pem)\" ];"
echo ""
echo "Service status:"
sudo systemctl status nix-serve --no-pager -l
echo ""
sudo systemctl status nginx --no-pager -l

# Optional: Setup SSL with Let's Encrypt
echo ""
read -p "Setup SSL certificate with Let's Encrypt? (y/n): " setup_ssl
if [[ "$setup_ssl" =~ ^[Yy]$ ]]; then
    echo "Setting up SSL certificate..."
    sudo certbot --nginx -d cachy.local --non-interactive --agree-tos --email admin@cachy.local
    echo "SSL certificate installed!"
fi

echo ""
echo "Installation complete! Binary cache is running at http://cachy.local"
echo "You can monitor logs with: sudo journalctl -u nix-serve -f"