#!/bin/bash

set -e

# Ensure script is run as root
[[ $EUID -ne 0 ]] && echo "Please run as root." && exit 1

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

print_usage() {
    echo "Usage: $0 -k <authkey> [-n <hostname>] [-e true|false] [-r <subnets|false>] [-s true|false]"
    echo ""
    echo "Options:"
    echo "  -k   Tailscale Auth Key (required)"
    echo "  -n   Hostname to register with Tailscale (default: current hostname)"
    echo "  -e   Advertise as exit node: true or false (default: ask)"
    echo "  -r   Advertise routes (subnets), e.g. 192.168.1.0/24 or 'false' to disable (default: ask)"
    echo "  -s   Enable Tailscale SSH: true or false (default: true)"
    exit 1
}

# Parse CLI args
while getopts "k:n:e:r:s:h" opt; do
    case ${opt} in
        k) TAILSCALE_AUTHKEY="$OPTARG" ;;
        n) TAILSCALE_HOSTNAME="$OPTARG" ;;
        e)
            EXIT_NODE_SET=1
            if [[ "$OPTARG" =~ ^[Yy]([Ee][Ss])?$ || "$OPTARG" == "true" ]]; then
                ENABLE_EXIT_NODE="--advertise-exit-node"
            else
                ENABLE_EXIT_NODE=""
            fi
            ;;
        r)
            ROUTES_SET=1
            if [[ "$OPTARG" != "false" && "$OPTARG" != "none" && -n "$OPTARG" ]]; then
                ADVERTISE_SUBNETS="--advertise-routes=$(echo "$OPTARG" | tr -d '[:space:]')"
            else
                ADVERTISE_SUBNETS=""
            fi
            ;;
        s)
            SSH_SET=1
            if [[ "$OPTARG" =~ ^[Yy]([Ee][Ss])?$ || "$OPTARG" == "true" ]]; then
                ENABLE_TAILSCALE_SSH="--ssh"
            else
                ENABLE_TAILSCALE_SSH=""
            fi
            ;;
        h) print_usage ;;
        *) print_usage ;;
    esac
done

# Prompt for auth key if not provided (secure input)
if [[ -z "$TAILSCALE_AUTHKEY" ]]; then
    echo
    read -srp "Enter Tailscale Auth Key: " TAILSCALE_AUTHKEY
    echo
    read -srp "Confirm Auth Key: " TAILSCALE_AUTHKEY_CONFIRM
    echo
    if [[ "$TAILSCALE_AUTHKEY" != "$TAILSCALE_AUTHKEY_CONFIRM" ]]; then
        echo "Auth keys do not match. Aborting."
        exit 1
    fi
fi

# Set default hostname if not provided
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-$(hostname)}

# Default SSH behavior if not set
if [[ -z "$SSH_SET" ]]; then
    ENABLE_TAILSCALE_SSH="--ssh"
fi

echo "Uninstalling any existing Tailscale and jq installations..."
{
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true
    apt-get remove --purge -y tailscale jq >/dev/null 2>&1 || true
    rm -f /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg
    apt-get update -y >/dev/null 2>&1
} & spinner $!

# Prompt if not set
if [[ -z "$EXIT_NODE_SET" ]]; then
    read -rp "Advertise this machine as an exit node? (y/N): " enable_exit
    if [[ "$enable_exit" =~ ^[Yy]$ ]]; then
        ENABLE_EXIT_NODE="--advertise-exit-node"
    fi
fi

if [[ -z "$ROUTES_SET" ]]; then
    read -rp "Advertise local subnets (e.g., 192.168.1.0/24)? (y/N): " enable_subnet
    if [[ "$enable_subnet" =~ ^[Yy]$ ]]; then
        read -rp "Enter subnet(s) to advertise (comma-separated): " SUBNETS
        if [[ -n "$SUBNETS" ]]; then
            ADVERTISE_SUBNETS="--advertise-routes=$(echo "$SUBNETS" | tr -d '[:space:]')"
        fi
    fi
fi

echo "Installing prerequisites (curl, gnupg2, jq)..."
{
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl gnupg2 jq >/dev/null 2>&1
} & spinner $!

echo "Adding Tailscale GPG key and repository..."
{
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.gpg | \
        gpg --yes --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu jammy main" \
        > /etc/apt/sources.list.d/tailscale.list
    apt-get update -y >/dev/null 2>&1
} & spinner $!

echo "Installing Tailscale..."
{
    apt-get install -y tailscale >/dev/null 2>&1
} & spinner $!

# Enable forwarding if needed
if [[ -n "$ENABLE_EXIT_NODE" || -n "$ADVERTISE_SUBNETS" ]]; then
    echo "Enabling IPv4 and IPv6 forwarding..."
    cat <<EOF | tee /etc/sysctl.d/99-tailscale.conf >/dev/null
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    sysctl --system 2>&1 | grep -v "Invalid argument" >/dev/null
fi

echo "Starting Tailscale and authenticating..."
systemctl enable --now tailscaled

# Start Tailscale with options
if ! tailscale up \
    --authkey "$TAILSCALE_AUTHKEY" \
    --hostname "$TAILSCALE_HOSTNAME" \
    $ENABLE_TAILSCALE_SSH \
    $ENABLE_EXIT_NODE \
    $ADVERTISE_SUBNETS \
    --accept-routes; then
    echo "Tailscale failed to connect. Check your auth key and network."
    exit 1
fi

echo ""
echo "Tailscale started successfully!"
echo "Tailscale IPv4 Address: $(tailscale ip -4)"
