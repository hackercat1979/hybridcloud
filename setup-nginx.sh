#!/bin/bash

set -e

spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "      \b\b\b\b\b\b"
}

echo -n "Updating system..."
(apt update -y >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1) & spinner
echo " done."

echo -n "Installing prerequisites..."
(apt install -y curl software-properties-common apt-transport-https ca-certificates ufw fail2ban >/dev/null 2>&1) & spinner
echo " done."

echo "Installing Tailscale..."
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh -e false -r false

echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh >/dev/null 2>&1
rm get-docker.sh

echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

echo "Creating Nginx Proxy Manager directory..."
mkdir -p /opt/nginx-proxy-manager
cd /opt/nginx-proxy-manager

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

echo "Starting Nginx Proxy Manager with Docker Compose..."
docker-compose up -d

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
echo
echo "IMPORTANT:"
echo "Access the Admin UI at: http://<tailscale-ip>:81"
echo "Default login is : admin@example.com / changeme"
echo "PLEASE change the default password immediately after first login."
echo
echo "Ports 80 and 443 are open for proxying your sites."
echo "Port 81 (admin UI) is restricted to Tailscale network."
