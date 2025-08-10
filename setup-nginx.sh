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

echo
echo "Please enter a password for the root user (used for SSH login):"
read -s -p "Password: " ROOT_PWD
echo
read -s -p "Confirm Password: " ROOT_PWD_CONFIRM
echo

if [ "$ROOT_PWD" != "$ROOT_PWD_CONFIRM" ]; then
    echo "Passwords do not match. Aborting."
    exit 1
fi

echo "root:$ROOT_PWD" | chpasswd

echo "Configuring SSH to allow root login with password..."
sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "Installing Tailscale..."
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh -e false -r false -s false

echo -n "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh &>/dev/null
(sh get-docker.sh &>/dev/null) & spinner
rm get-docker.sh
echo " done."

echo -n "Installing Docker Compose..."
curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose &>/dev/null &
spinner
chmod +x /usr/local/bin/docker-compose
echo " done."

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
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

echo -n "Starting Nginx Proxy Manager containers..."
docker-compose up -d &>/dev/null &
spinner
echo " done."

echo "Configuring firewall with UFW..."
ufw default deny incoming
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 100.64.0.0/10 to any port 81 proto tcp
ufw allow from 100.64.0.0/10 to any port 22 proto tcp
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

TAILSCALE_IP=$(tailscale ip -4 | grep '^100\.')

echo
echo "Nginx Proxy Manager setup complete!"
if [ -n "$TAILSCALE_IP" ]; then
    echo "Access the Admin UI at: http://$TAILSCALE_IP:81"
else
    echo "Access the Admin UI at: http://<tailscale-ip>:81 (Tailscale IP not detected)"
fi
echo "PLEASE change the default password immediately after first login."
echo
echo "Ports 80 and 443 are open for proxying your sites."
echo "Port 81 (admin UI) is restricted to Tailscale network."
