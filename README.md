# hybridcloud

With This REPO you can do a basic Hybrid Cloud setup

1) Install NGINX Proxy manager

curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-nginx.sh -o setup-nginx.sh
sed -i 's/\r$//' setup-nginx.sh
bash setup-nginx.sh

2) Install Authentik
   
curl -fsSL https://raw.githubusercontent.com/hackercat1979/hybridcloud/main/setup-authentik.sh -o setup-authentik.sh
sed -i 's/\r$//' setup-authentik.sh
bash setup-authentik.sh
