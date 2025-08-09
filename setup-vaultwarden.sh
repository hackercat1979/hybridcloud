#!/bin/bash

set -e

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r[%c] " "${spinstr:i++%${#spinstr}:1}"
        sleep $delay
    done
    printf "\r    \r"
}

echo "Updating system..."
(apt update -y >/dev/null 2>&1 && apt upgrade -y >/dev/null 2>&1) & spinner $!
echo "System updated."

echo "Installing prerequisites..."
(apt install -y curl docker.io docker-compose ufw fail2ban >/dev/null 2>&1) & spinner $!
echo "Prerequisites installed."

echo "Installing Tailscale..."
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh -e false -r false -s false

echo "Creating vaultwarden directory..."
mkdir -p /opt/vaultwarden
cd /opt/vaultwarden

echo "Writing docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: "3"
services:
  vaultwarden:
    image: vaultwarden/server:latest
    restart: unless-stopped
    ports:
      - "8080:8080"
      - "8443:8443"
    volumes:
      - ./vw-data:/data
EOF

echo "Starting Vaultwarden container..."
docker-compose up -d & spinner $!
echo "Vaultwarden is running."

echo "Configuring firewall with UFW..."

ufw default deny incoming
ufw default allow outgoing

ufw allow in on tailscale0 to any port 22 proto tcp
ufw allow in on tailscale0 to any port 8080 proto tcp
ufw allow in on tailscale0 to any port 8443 proto tcp
ufw --force enable

echo "Firewall configured."

echo "Configuring fail2ban..."
cat > /etc/fail2ban/jail.local <<EOL
[DEFAULT]
bantime = 10m
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[docker-vaultwarden-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/docker-vaultwarden/error.log
maxretry = 3
EOL

systemctl restart fail2ban

TAILSCALE_IP=$(tailscale ip -4 | grep '^100\.')
echo
echo "Vaultwarden setup complete!"
if [ -n "$TAILSCALE_IP" ]; then
    echo "Access Vaultwarden UI at: http://$TAILSCALE_IP:8080 or https://$TAILSCALE_IP:8443"
else
    echo "Access Vaultwarden UI at: http://<tailscale-ip>:8080 or https://<tailscale-ip>:8443 (Tailscale IP not detected)"
fi

echo
echo "Note: SSH and Vaultwarden are only accessible via Tailscale VPN."
echo "Public internet access to these ports is blocked."
