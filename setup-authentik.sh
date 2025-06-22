#!/bin/bash
set -e

spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    for (( i=0; i<${#spinstr}; i++ )); do
      printf "\r%s" "${spinstr:i:1}"
      sleep $delay
    done
  done
  printf "\r"
}

echo "Installing Tailscale ..."
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh -n de-flk-authentik -e false -r false

echo "Starting install Authentik ..."

echo "Installing dependencies..."
apt update -qq &>/dev/null
apt install -y -qq curl ca-certificates software-properties-common apt-transport-https gnupg lsb-release openssl fail2ban &>/dev/null &
spinner $!
echo "Dependencies installed."

if ! command -v docker >/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh &>/dev/null
  sh get-docker.sh &>/dev/null &
  spinner $!
  rm get-docker.sh
  echo "Docker installed."
else
  echo "Docker already installed."
fi

if ! command -v docker-compose >/dev/null; then
  echo "Installing Docker Compose..."
  curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose &>/dev/null &
  spinner $!
  chmod +x /usr/local/bin/docker-compose
  echo "Docker Compose installed."
else
  echo "Docker Compose already installed."
fi

echo "Preparing Authentik directory..."
mkdir -p /opt/authentik/
cd /opt/authentik

echo "Downloading docker-compose.yml..."
wget -q https://goauthentik.io/docker-compose.yml

echo "Generating environment variables..."
echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" > .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
echo "AUTHENTIK_ERROR_REPORTING__ENABLED=true" >> .env

echo "Pulling Authentik docker images..."
docker-compose pull &>/dev/null &
spinner $!
echo "Images pulled."

echo "Starting Authentik containers..."
docker-compose up -d &>/dev/null &
spinner $!
echo "Authentik started."

if command -v tailscale >/dev/null; then
  TAILSCALE_IP=$(tailscale ip -4 | head -n1)
  if [ -z "$TAILSCALE_IP" ]; then
    TAILSCALE_IP="(Tailscale installed but no IP assigned)"
  fi
else
  TAILSCALE_IP="(Tailscale CLI not found)"
fi

echo
echo "Authentik is now running on port 9000."
echo "Access setup: http://$TAILSCALE_IP:9000/if/flow/initial-setup/"
echo "Recommended: Put Authentik behind Nginx Proxy Manager (e.g., https://auth.yourdomain.com)"
echo "If Tailscale is not connected, you will not be able to access via Tailscale IP."

echo "Installing and configuring UFW to allow only Tailscale access..."

apt install -y -qq ufw &>/dev/null

# Default deny all incoming traffic from the internet
ufw default deny incoming
ufw default allow outgoing

# Allow SSH from Tailscale
ufw allow in on tailscale0 to any port 22 proto tcp

# Allow Authentik internal HTTP (9000) and HTTPS (9443) from Tailscale
ufw allow in on tailscale0 to any port 9000 proto tcp
ufw allow in on tailscale0 to any port 9443 proto tcp

# Enable the firewall
ufw --force enable

echo "UFW enabled with Tailscale-only access to SSH, Authentik HTTP (9000), and HTTPS (9443)."

