# hybridcloud

With This REPO you can do a basic Hybrid Cloud setup

1) For each Cloud Machine you need install Taiscale :

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/install-nginx.sh -o install-nginx.sh
sed -i 's/\r$//' install-nginx.sh
bash install-nginx.sh

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-authentik.sh -o setup-authentik.sh
sed -i 's/\r$//' setup-authentik.sh
bash setup-authentik.sh
