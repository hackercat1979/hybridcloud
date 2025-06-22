curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh
