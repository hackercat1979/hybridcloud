#!/bin/bash
set -e
echo "📦 Installing Tailscale ..."
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-vpn.sh -o setup-vpn.sh
sed -i 's/\r$//' setup-vpn.sh
bash setup-vpn.sh -n de-flk-authentik -e false -r false #-k and keydata

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
  echo "📦 Installing Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
fi

# Create directory structure
mkdir -p /opt/authentik/
cd /opt/authentik

# Download docker-compose.yml
wget https://goauthentik.io/docker-compose.yml

#generate a password
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
echo "AUTHENTIK_ERROR_REPORTING__ENABLED=true" >> .env

echo "📦 Pulling Authentik..."
docker-compose pull

echo "➡️ Starting Authentik..."
docker-compose up -d

AUTHENTIK_URL="http://localhost:9000/if/flow/initial-setup/"
MAX_RETRIES=60  # wait up to 2 minutes (60 * 2s)
RETRIES=0

echo -n "⏳ Waiting for Authentik backend to be ready"

while true; do
  RESPONSE=$(curl -s "$AUTHENTIK_URL")
  
  if [[ "$RESPONSE" != *"failed to connect to authentik backend: authentik starting"* ]]; then
    echo -e "\n✅ Authentik backend is ready!"
    break
  fi

  ((RETRIES++))
  if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    echo -e "\n❌ Timeout waiting for Authentik backend."
    exit 1
  fi

  echo -n "."
  sleep 2
done


# OPTIONAL: Configure firewall (commented out for testing)
#: '
#echo "🛡️ Configuring UFW (optional)..."
#ufw default deny incoming
#ufw allow from 100.64.0.0/10 to any port 9000 proto tcp   # Allow Authentik via Tailscale only
# ufw allow 80,443/tcp   # Uncomment if proxying via Nginx Proxy Manager
# ufw allow 22/tcp       # Uncomment if SSH access is needed
#ufw --force enable
#'

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
