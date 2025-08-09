#!/bin/bash
set -euo pipefail

echo "Updating system..."
apt update -y && apt upgrade -y
echo "System updated."

echo "Installing prerequisites..."
apt install -y curl docker.io docker-compose ufw fail2ban
systemctl enable --now docker
echo "Prerequisites installed."

echo "Creating vaultwarden directory..."
mkdir -p /opt/vaultwarden
cd /opt/vaultwarden

echo "Writing docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: "3"
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden-vaultwarden-1
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"    # Vaultwarden HTTP localhost only
      - "127.0.0.1:8443:443"   # Vaultwarden HTTPS localhost only
    volumes:
      - ./vw-data:/data
EOF

echo "Starting Vaultwarden container..."
docker-compose up -d --remove-orphans

echo "Configuring firewall (UFW)..."

# Allow Vaultwarden ports only from Tailscale subnet
ufw allow from 100.64.0.0/10 to any port 8080 proto tcp comment "Vaultwarden HTTP localhost"
ufw allow from 100.64.0.0/10 to any port 8443 proto tcp comment "Vaultwarden HTTPS localhost"

# Enable UFW if not active
if ! ufw status | grep -q active; then
  ufw --force enable
fi

echo "Firewall configured."

echo "Configuring basic fail2ban for SSH..."
cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF

systemctl restart fail2ban

echo "Vaultwarden setup complete!"
echo ""
echo "Access Vaultwarden UI via Tailscale IP:"
echo "  http://$(tailscale ip -4):8080"
echo "  https://$(tailscale ip -4):8443"
echo ""
echo "IMPORTANT:"
echo "- Vaultwarden is only accessible via localhost ports; use a reverse proxy (like Nginx Proxy Manager) if you want public HTTPS access."
echo "- SSH and Vaultwarden ports are restricted to Tailscale VPN IP range."
