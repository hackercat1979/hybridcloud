#!/bin/bash
set -e

echo "🔧 Installing Authentik on Ubuntu 22.04..."

# Update system and install dependencies
apt update && apt install -y \
  curl ca-certificates software-properties-common apt-transport-https gnupg lsb-release openssl \
  ufw fail2ban

# Install Docker
if ! command -v docker >/dev/null; then
  echo "🐳 Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
fi

# Install Docker Compose
if ! command -v docker-compose >/dev/null; then
  echo "📦 Installing Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Generate secret key
SECRET_KEY=$(openssl rand -hex 32)

# Setup directories
mkdir -p /opt/authentik/{postgresql,media,templates}
cd /opt/authentik

# Create docker-compose.yml
echo "📝 Writing docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: "3.4"

services:
  redis:
    image: redis:alpine
    restart: unless-stopped

  postgresql:
    image: postgres:13
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: authentikpassword
      POSTGRES_USER: authentik
      POSTGRES_DB: authentik
    volumes:
      - ./postgresql:/var/lib/postgresql/data

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    depends_on:
      - postgresql
      - redis
    environment:
      AUTHENTIK_SECRET_KEY: ${SECRET_KEY}
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: authentikpassword
      AUTHENTIK_POSTGRESQL__NAME: authentik
    volumes:
      - ./media:/media
      - ./templates:/templates
    ports:
      - "9000:9000"

  authentik-worker:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    depends_on:
      - authentik-server
    environment:
      AUTHENTIK_SECRET_KEY: ${SECRET_KEY}
      AUTHENTIK_REDIS__HOST: redis
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__USER: authentik
      AUTHENTIK_POSTGRESQL__PASSWORD: authentikpassword
      AUTHENTIK_POSTGRESQL__NAME: authentik
    volumes:
      - ./media:/media
      - ./templates:/templates
EOF

# Launch containers
echo "🚀 Starting Authentik..."
docker-compose up -d

# Configure firewall
echo "🔒 Setting up UFW (firewall)..."
ufw --force reset
ufw default deny incoming
ufw allow from 100.64.0.0/10 to any port 22 proto tcp     # SSH via Tailscale
ufw allow from 100.64.0.0/10 to any port 9000 proto tcp   # Authentik UI via Tailscale

# OPTIONAL: If reverse proxying Authentik publicly
# ufw allow 80/tcp     # HTTP (optional public access)
# ufw allow 443/tcp    # HTTPS (optional public access)

ufw --force enable

echo
echo "✅ Authentik is running on port 9000 (via Tailscale)."
echo "➡️  Access setup: http://<tailscale-ip>:9000/if/flow/initial-setup/"
echo "🔐 SSH is only allowed through the Tailscale network (port 22 restricted)."
echo "🛡️  Fail2Ban installed (protects against brute force attacks)."
echo "🌐 Recommendation: Add Authentik behind Nginx Proxy Manager if exposing to the web."
