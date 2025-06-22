#!/bin/bash

set -e

# -------- USER PROMPTS --------
read -rsp "Enter your Tailscale Auth Key: " TAILSCALE_AUTHKEY
echo ""
if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
    echo "Error: No auth key provided. Exiting."
    exit 1
fi

read -rp "Enter hostname to register with Tailscale (default: $(hostname)): " TAILSCALE_HOSTNAME
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-$(hostname)}

ADVERTISE_EXIT_NODE=""
ADVERTISE_SUBNETS=""

read -rp "Advertise this machine as an exit node? (y/N): " enable_exit
if [[ "$enable_exit" =~ ^[Yy]$ ]]; then
    ADVERTISE_EXIT_NODE="--advertise-exit-node"
fi

read -rp "Advertise local subnets (e.g., 192.168.1.0/24)? (y/N): " enable_subnet
if [[ "$enable_subnet" =~ ^[Yy]$ ]]; then
    read -rp "Enter subnet(s) to advertise (comma-separated, e.g., 192.168.1.0/24,10.0.0.0/16): " SUBNETS
    if [[ -n "$SUBNETS" ]]; then
        ADVERTISE_SUBNETS="--advertise-routes=${SUBNETS// /}"
    fi
fi

# -------- INSTALL TAILSCALE AND JQ --------
echo "Installing Tailscale and jq..."

apt-get update -y
apt-get install -y curl gnupg2 jq

# Add GPG key and APT repository (overwrite keyring silently)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.gpg | gpg --yes --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" > /etc/apt/sources.list.d/tailscale.list

apt-get update -y
apt-get install -y tailscale

# -------- ENABLE IP FORWARDING IF NEEDED --------
if [[ -n "$ADVERTISE_EXIT_NODE" || -n "$ADVERTISE_SUBNETS" ]]; then
    echo "Enabling IPv4 and IPv6 forwarding for exit node and subnet routing..."

    cat <<EOF | tee /etc/sysctl.d/99-tailscale.conf >/dev/null
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    # Suppress only "Invalid argument" warnings
    sysctl --system 2>&1 | grep -v "Invalid argument"
fi

# -------- START AND AUTHENTICATE --------
echo "Starting Tailscale and authenticating..."

systemctl enable --now tailscaled

tailscale up \
    --authkey "$TAILSCALE_AUTHKEY" \
    --hostname "$TAILSCALE_HOSTNAME" \
    --ssh \
    $ADVERTISE_EXIT_NODE \
    $ADVERTISE_SUBNETS \
    --accept-routes

# -------- OUTPUT --------
echo ""
echo "✅ Tailscale started successfully!"
echo "🌐 Tailscale IPv4 Address:"
tailscale ip -4

