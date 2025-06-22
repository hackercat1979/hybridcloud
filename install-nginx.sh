#!/bin/bash

set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing prerequisites..."
apt install -y curl software-properties-common apt-transport-https ca-certificates

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

echo "Installation complete!"
echo "Access the admin UI at http://YOUR_SERVER_IP:81"
echo "Default credentials: admin@example.com / changeme"
