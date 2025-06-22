#!/bin/bash
set -e

echo "📦 Installing dependencies..."
apt update && apt install -y curl ca-certificates software-properties-common apt-transport-https gnupg lsb-release openssl fail2ban

# Install Docker if missing
if ! command -v docker >/dev/null; then
  echo "🐳 Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
fi

# Install Docker Compose if missing
if ! command -v docker-compose >/dev/null; then
  echo "🔧 Installing Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Generate secure secret key
SECRET_KEY=$(openssl rand -hex 32)

# Create directory structure
mkdir -p /opt/authentik/{db,redis,media,templates}
cd /opt/authentik

echo "📝 Writing docker-compose.yml..."

cat > docker-compose.yml <<EOF
version: "3.4"

services:
  redis:
    image: redis:alpine
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - ./redis:/data

  postgresql:
    image: postgres:13
    restart: unless-stopped
    environment:
      POSTGRES_PASSWORD: authentikpassword
      POSTGRES_USER: authentik
      POSTGRES_DB: authentik
    volumes:
      - ./db:/var/lib/postgresql/data

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    depends_on:
      - postgresql
      - redis
    ports:
      - "9000:9000"
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

echo "🚀 Starting Authentik..."
docker-compose up -d

# OPTIONAL: Configure firewall (commented out for testing)
: '
echo "🛡️ Configuring UFW (optional)..."
ufw default deny incoming
ufw allow from 100.64.0.0/10 to any port 9000 proto tcp   # Allow Authentik via Tailscale only
# ufw allow 80,443/tcp   # Uncomment if proxying via Nginx Proxy Manager
# ufw allow 22/tcp       # Uncomment if SSH access is needed
ufw --force enable
'

# Detect Tailscale IP for output
if command -v tailscale >/dev/null; then
  TAILSCALE_IP=$(tailscale ip -4 | head -n1)
  if [ -z "$TAILSCALE_IP" ]; then
    TAILSCALE_IP="(Tailscale installed but no IP assigned)"
  fi
else
  TAILSCALE_IP="(Tailscale CLI not found)"
fi

echo
echo "✅ Authentik is now running on port 9000."
echo "➡️  Access setup: http://$TAILSCALE_IP:9000/if/flow/initial-setup/"
echo "👉 Recommended: Put Authentik behind Nginx Proxy Manager (e.g., https://auth.yourdomain.com)"
echo "⚠️  If Tailscale is not connected, you will not be able to access via Tailscale IP."
