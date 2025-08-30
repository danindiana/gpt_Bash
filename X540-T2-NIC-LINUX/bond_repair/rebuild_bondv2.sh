#!/usr/bin/env bash
set -euo pipefail

# ==== SETTINGS (adjust if your ifnames differ) ====
BOND="bond0"
IF_A="enp3s0f0"    # X540 port A
IF_B="enp3s0f1"    # X540 port B
BACKUP_IF="enp9s0" # onboard I211
BOND_METRIC="50"
BACKUP_METRIC="200"
STATIC_IP="192.168.1.97/24"  # Recommended static IP for stability
GATEWAY="192.168.1.254"
DNS_SERVERS="1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4"  # Cloudflare + Google DNS

echo "==> Ensuring NetworkManager is the only owner (no netplan/ifupdown conflicts)..."
sudo mkdir -p /etc/netplan/backup-$(date +%Y%m%d)
for f in /etc/netplan/*; do
  # Move any netplan file except our minimal NM handoff
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  if [[ "$base" != "00-use-NM.yaml" ]]; then
    sudo mv "$f" "/etc/netplan/backup-$(date +%Y%m%d)/" 2>/dev/null || true
  fi
done

# Minimal netplan that hands control to NM
cat <<'YAML' | sudo tee /etc/netplan/00-use-NM.yaml >/dev/null
network:
  version: 2
  renderer: NetworkManager
YAML
sudo chown root:root /etc/netplan/00-use-NM.yaml
sudo chmod 600 /etc/netplan/00-use-NM.yaml
sudo netplan generate
sudo netplan apply

# Silence noisy dispatcher script if present
if [ -e /etc/NetworkManager/dispatcher.d/01-ifupdown.DISABLED ]; then
  sudo mv /etc/NetworkManager/dispatcher.d/01-ifupdown.DISABLED \
          /etc/NetworkManager/dispatcher.d/01-ifupdown.disabled.bak
fi

echo "==> Stopping NetworkManager for clean restart..."
sudo systemctl stop NetworkManager

echo "==> Cleaning up network state..."
# Kill all DHCP clients and flush IP addresses
sudo pkill -f dhclient || true
sudo ip addr flush dev "$BOND" 2>/dev/null || true
sudo ip addr flush dev "$IF_A" 2>/dev/null || true
sudo ip addr flush dev "$IF_B" 2>/dev/null || true
sudo ip addr flush dev "$BACKUP_IF" 2>/dev/null || true
sudo ip route flush all 2>/dev/null || true

# Bring down interfaces to ensure clean state
sudo ip link set dev "$IF_A" down 2>/dev/null || true
sudo ip link set dev "$IF_B" down 2>/dev/null || true
sudo ip link set dev "$BACKUP_IF" down 2>/dev/null || true

echo "==> Removing any kernel bond device left behind..."
sudo ip link delete "$BOND" type bond 2>/dev/null || true
sudo modprobe -r bonding 2>/dev/null || true
sudo modprobe bonding

echo "==> Cleaning duplicate/ghost NetworkManager connections..."
# Remove all existing connections to ensure clean slate
sudo rm -f /etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null || true

echo "==> Starting NetworkManager..."
sudo systemctl start NetworkManager
sleep 3

echo "==> Recreating bond0 with SIMPLIFIED bonding options..."
# Use minimal bonding options to avoid attribute setting failures
sudo nmcli con add type bond ifname "$BOND" con-name "$BOND" \
  bond.options "mode=802.3ad,miimon=100"  # Simplified to avoid attribute errors

# Use STATIC IP for stability (highly recommended over DHCP)
sudo nmcli con mod "$BOND" \
  ipv4.method manual \
  ipv4.addresses "$STATIC_IP" \
  ipv4.gateway "$GATEWAY" \
  ipv4.dns "$DNS_SERVERS" \
  ipv4.route-metric "$BOND_METRIC" \
  ipv4.ignore-auto-dns yes \
  ipv6.method ignore

echo "==> Adding X540 ports as slaves with EXPLICIT IP disabling..."
# Create slave connections with IP methods explicitly disabled
sudo nmcli con add type ethernet ifname "$IF_A" master "$BOND" \
  con-name "bond-slave-$IF_A" \
  ipv4.method disabled \
  ipv6.method ignore

sudo nmcli con add type ethernet ifname "$IF_B" master "$BOND" \
  con-name "bond-slave-$IF_B" \
  ipv4.method disabled \
  ipv6.method ignore

echo "==> Configuring onboard NIC as independent backup..."
sudo nmcli con add type ethernet ifname "$BACKUP_IF" con-name "onboard-eth" \
  ipv4.method auto \
  ipv4.route-metric "$BACKUP_METRIC" \
  ipv6.method ignore

echo "==> Setting proper permissions on NetworkManager connections..."
sudo chmod 600 /etc/NetworkManager/system-connections/* || true

echo "==> Restarting NetworkManager to apply all changes..."
sudo systemctl restart NetworkManager
sleep 5

echo "==> Bringing everything up in correct order..."
# Bring slaves up first, then bond, then backup interface
sudo nmcli con up "bond-slave-$IF_A"
sudo nmcli con up "bond-slave-$IF_B"
sleep 2  # Wait for slaves to initialize
sudo nmcli con up "$BOND"
sudo nmcli con up "onboard-eth"

echo "==> Cleaning stray routes and DHCP processes..."
sudo ip route del default dev "$IF_A" 2>/dev/null || true
sudo ip route del default dev "$IF_B" 2>/dev/null || true
sudo pkill -f "dhclient.*$IF_A" || true
sudo pkill -f "dhclient.*$IF_B" || true

echo "==> Waiting for network stabilization..."
sleep 5

echo "==> Final status:"
echo "NetworkManager connections:"
nmcli -f NAME,UUID,TYPE,DEVICE,STATE con show | column -t

echo -e "\nBond status:"
if [ -e "/proc/net/bonding/$BOND" ]; then
  cat "/proc/net/bonding/$BOND"
else
  echo "Bond interface not available yet"
fi

echo -e "\nIP addresses:"
ip -4 addr show "$BOND" 2>/dev/null || echo "Bond0 not configured"
ip -4 addr show "$IF_A" 2>/dev/null || echo "$IF_A not configured"
ip -4 addr show "$IF_B" 2>/dev/null || echo "$IF_B not configured"
ip -4 addr show "$BACKUP_IF" 2>/dev/null || echo "$BACKUP_IF not configured"

echo -e "\nRouting table:"
ip route

echo -e "\nDNS configuration:"
nmcli device show "$BOND" | grep DNS || echo "No DNS configured on bond0"

echo
echo "✅ Done. bond0 should have static IP $STATIC_IP with DNS: $DNS_SERVERS"
echo "   Both $IF_A and $IF_B should appear as slaves with NO IP addresses."
echo "   enp9s0 should be a backup interface with higher metric ($BACKUP_METRIC)."

# Test connectivity
echo -e "\nTesting connectivity..."
if ping -c 2 -W 1 "$GATEWAY" &>/dev/null; then
    echo "✓ Gateway $GATEWAY is reachable"
else
    echo "✗ Gateway $GATEWAY is not reachable - check switch configuration"
    echo "   On SG300-28, ensure:"
    echo "   1. LACP is enabled on switch ports"
    echo "   2. Ports are in correct VLAN"
    echo "   3. Switch has proper routing configured"
fi
