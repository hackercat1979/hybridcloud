#!/bin/bash
set -e

spinner() {
    # Simple spinner animation while command runs in background
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r[%c] " "${spinstr:i:1}"
            sleep $delay
        done
    done
    printf "\r    \r"
}

echo "Uninstalling any existing Tailscale and jq installations..."

{
    sudo systemctl stop tailscaled || true
    sudo systemctl disable tailscaled || true
    sudo apt-get remove --purge -y tailscale jq || true
    sudo rm -f /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg || true
    sudo apt-get update -y
} & spinner $!

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

# -------- INSTALL TAILSCALE & JQ --------
echo "Installing Tailscale and jq..."

{
    sudo apt-get install -y curl gnupg2 jq
} & spinner $!

echo "Adding Tailscale GPG key and repository..."

{
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt-get update -y
} & spinner $!

echo "Installing tailscale..."

{
    sudo apt-get install -y tailscale
} & spinner $!

# -------- ENABLE IP FORWARDING IF NEEDED --------
if [[ -n "$ADVERTISE_EXIT_NODE" || -n "$ADVERTISE_SUBNETS" ]]; then
    echo "Enabling IPv4 and IPv6 forwarding for exit node and subnet routing..."

    sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF

    # Suppress "Invalid argument" warnings
    sudo sysctl --system 2>&1 | grep -v "Invalid argument"
fi

# -------- START AND AUTHENTICATE --------
echo "Starting Tailscale and authenticating..."

sudo systemctl enable --now tailscaled

sudo tailscale up \
    --authkey "$TAILSCALE_AUTHKEY" \
    --hostname "$TAILSCALE_HOSTNAME" \
    --ssh \
    $ADVERTISE_EXIT_NODE \
    $ADVERTISE_SUBNETS

# -------- OUTPUT --------
echo ""
echo "✅ Tailscale started successfully!"
echo "🌐 Tailscale IPv4 Address:"
tailscale ip -4
