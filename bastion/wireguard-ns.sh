# Extract configuration from wg0.conf file
export WG_ADDRESS=$(awk '/^Address/ {gsub(/Address = /, ""); print}' /etc/wireguard/wg0.conf)
export WG_PRIVATE_KEY=$(awk '/^PrivateKey/ {gsub(/PrivateKey = /, ""); print}' /etc/wireguard/wg0.conf)
export WG_MTU=$(awk '/^MTU/ {gsub(/MTU = /, ""); print}' /etc/wireguard/wg0.conf)
export WG_DNS=$(awk '/^DNS/ {gsub(/DNS = /, ""); print}' /etc/wireguard/wg0.conf)

export WG_PUBLIC_KEY=$(awk '/^PublicKey/ {gsub(/PublicKey = /, ""); print}' /etc/wireguard/wg0.conf)
export WG_PRESHARED_KEY=$(awk '/^PresharedKey/ {gsub(/PresharedKey = /, ""); print}' /etc/wireguard/wg0.conf)
export WG_ENDPOINT=$(awk '/^Endpoint/ {gsub(/Endpoint = /, ""); print}' /etc/wireguard/wg0.conf)
export WG_PERSISTENT_KEEPALIVE=$(awk '/^PersistentKeepalive/ {gsub(/PersistentKeepalive = /, ""); print}' /etc/wireguard/wg0.conf)


      

echo "Config extracted: Address=$WG_ADDRESS, PrivateKey=$WG_PRIVATE_KEY, MTU=$WG_MTU, DNS=$WG_DNS"
echo "PublicKey=$WG_PUBLIC_KEY, PresharedKey=$WG_PRESHARED_KEY, Endpoint=$WG_ENDPOINT, PersistentKeepalive=$WG_PERSISTENT_KEEPALIVE"


# Step 1: Create WireGuard interface in main namespace (where it can reach internet)
ip link add wg0 type wireguard

# Step 2: Set MTU before configuring crypto (important for some networks)
ip link set wg0 mtu $WG_MTU

# Step 3: Configure WireGuard crypto and peer settings in main namespace
wg set wg0 \
private-key <(echo "$WG_PRIVATE_KEY") \
peer "$WG_PUBLIC_KEY" \
preshared-key <(echo "$WG_PRESHARED_KEY") \
allowed-ips 0.0.0.0/0 \
endpoint "$WG_ENDPOINT" \
persistent-keepalive "$WG_PERSISTENT_KEEPALIVE"

# Move to namespace BEFORE adding IP/routes
ip netns add wg-ns
# create loopback in namespace
ip netns exec wg-ns ip link set lo up
ip netns exec wg-ns ip addr add 127.0.0.1/8 dev lo
#ip link set wg0 netns wg-ns

# can use 'ip link set wg0 netns wg-ns up' to put in wg-ns and online in one command
ip link set wg0 netns wg-ns up

#ip netns exec wg-ns ip link set wg0 up
ip netns exec wg-ns ip addr add $WG_ADDRESS dev wg0
ip netns exec wg-ns ip route add default dev wg0

# dnsmasq with TTL control
ip netns exec wg-ns dnsmasq \
  --no-daemon \
  --server=$WG_DNS \
  --cache-size=10000 \
  --min-cache-ttl=300 \
  --max-cache-ttl=86400 \
  --listen-address=127.0.0.1 \
  --port=53 \
  --no-resolv &

mkdir -p /etc/netns/wg-ns
echo "nameserver 127.0.0.1" > /etc/netns/wg-ns/resolv.conf
echo "nameserver $WG_DNS" >> /etc/netns/wg-ns/resolv.conf


# OLD BELOW

# Step 4: Bring interface up in main namespace to establish handshake
ip link set wg0 up

# Step 5: Add IP address to the interface (this was missing!)
ip addr add $WG_ADDRESS dev wg0
# ip netns exec wg-ns ip addr add $WG_ADDRESS dev wg0

# Step 6: Set up routing (this is the crucial part you were missing)
# First, preserve SSH connectivity by adding specific route to your current gateway
ip route add 10.0.0.0/20 dev ens4 scope link

# Step 7: Route external traffic through WireGuard
# Split default route to avoid conflicts (common WireGuard technique)
ip route add 0.0.0.0/1 dev wg0
ip route add 128.0.0.0/1 dev wg0

# Step 8: Update DNS (optional, but recommended for full VPN functionality)
# Backup current resolv.conf and set VPN DNS
cp /etc/resolv.conf /etc/resolv.conf.backup
echo "nameserver 127.0.0.1" > /etc/resolv.conf
echo "nameserver $WG_DNS" > /etc/resolv.conf

# test commands

wg show
ip netns exec wg-ns wg show

ip netns exec wg-ns ping 8.8.8.8
ip netns exec wg-ns curl -s --max-time 10 ifconfig.me
curl -s --max-time 10 ifconfig.me
ip netns exec wg-ns strace -e trace=sendto,recvfrom curl -s --max-time 5 disney.com 2>&1 | grep ":53"