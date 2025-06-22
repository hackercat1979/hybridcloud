# hybridcloud

With This REPO you can do a basic Hybrid Cloud setup

1) For each Cloud Machine you need install Taiscale :

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-tailscale.sh -o setup-tailscale.sh
sed -i 's/\r$//' setup-tailscale.sh
bash setup-tailscale.sh

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-vpn.sh -o setup-vpn.sh
sed -i 's/\r$//' setup-vpn.sh
bash setup-vpn.sh -k tskey-auth-k23TFtWpoG11CNTRL-HxWzktC1vVSqpQS6B2gLVSQwRsNqgqnrV -n de-flk-authentik -e false -r false

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/install-nginx.sh -o install-nginx.sh
sed -i 's/\r$//' install-nginx.sh
bash install-nginx.sh

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-authentik.sh -o setup-authentik.sh
sed -i 's/\r$//' setup-authentik.sh
bash setup-authentik.sh
