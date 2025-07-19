#!/bin/bash

set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing prerequisites..."
apt install -y curl software-properties-common apt-transport-https ca-certificates ufw fail2ban

echo "Installing Tailscale ..."
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh -e false -r false -s false

echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Creating Nginx Proxy Manager directory..."
mkdir -p /opt/nginx-proxy-manager
cd /opt/nginx-proxy-manager

echo "Configure Nginx Proxy Manager default admin user..."
read -rp "Enter admin email address: " ADMIN_EMAIL

while true; do
    read -rsp "Enter admin password: " ADMIN_PASS
    echo
    read -rsp "Confirm admin password: " ADMIN_PASS_CONFIRM
    echo
    if [ "$ADMIN_PASS" = "$ADMIN_PASS_CONFIRM" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

echo "Writing docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: "3"
services:
  app:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - "80:80"       # HTTP
      - "81:81"       # Admin UI
      - "443:443"     # HTTPS
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

echo "Creating default.json with provided credentials..."
mkdir -p /opt/nginx-proxy-manager/data
cat > /opt/nginx-proxy-manager/data/default.json <<EOF
{
  "default_user": {
    "email": "$ADMIN_EMAIL",
    "password": "$ADMIN_PASS"
  }
}
EOF
chown -R 1000:1000 /opt/nginx-proxy-manager/data

echo "Starting Nginx Proxy Manager with Docker Compose..."
docker-compose up -d

# Wait for container to consume default.json
echo "Waiting for NPM to initialize (10s)..."
sleep 10

# Remove sensitive default.json
echo "Removing default.json for security..."
rm -f /opt/nginx-proxy-manager/data/default.json

echo "Configuring firewall with UFW..."
ufw default deny incoming
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 100.64.0.0/10 to any port 81 proto tcp
ufw --force enable

echo "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<EOL
[DEFAULT]
bantime = 10m
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[docker-nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
EOL

systemctl restart fail2ban

echo
echo "Nginx Proxy Manager setup complete!"
echo "Access Admin UI via Tailscale IP at: http://<tailscale-ip>:81"
echo "To expose services, use DNS + Proxy Host settings in the web UI."
