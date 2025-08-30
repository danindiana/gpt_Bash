#!/usr/bin/env bash
set -euo pipefail

# ==== SETTINGS (adjust if your ifnames differ) ====
BOND="bond0"
IF_A="enp3s0f0"    # X540 port A
IF_B="enp3s0f1"    # X540 port B
BACKUP_IF="enp9s0" # onboard I211
BOND_METRIC="50"
BACKUP_METRIC="200"

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

echo "==> Cleaning duplicate/ghost NetworkManager connections..."
# Delete duplicate bond connections (keep none; we'll recreate)
while read -r uuid; do
  [ -n "$uuid" ] && sudo nmcli -g UUID,TYPE,DEVICE con show "$uuid" >/dev/null 2>&1 && \
    sudo nmcli con delete "$uuid" || true
done < <(nmcli -g UUID,TYPE,DEVICE con show | awk -F: -v b="$BOND" '$2=="bond"{print $1}')

# Delete any profiles tied directly to the X540 ports (we'll recreate as bond slaves)
for IFX in "$IF_A" "$IF_B"; do
  while read -r uuid; do
    [ -n "$uuid" ] && sudo nmcli con delete "$uuid" || true
  done < <(nmcli -g UUID,TYPE,DEVICE con show | awk -F: -v d="$IFX" '$3==d{print $1}')
done

# Delete stale "Wired connection *" ghosts
for name in "Wired connection 1" "Wired connection 2" "Wired connection 3" ; do
  sudo nmcli con delete "$name" 2>/dev/null || true
done

echo "==> Removing any kernel bond device left behind..."
sudo ip link delete "$BOND" type bond 2>/dev/null || true
sudo modprobe -r bonding 2>/dev/null || true
sudo modprobe bonding

echo "==> Recreating bond0 (802.3ad, miimon=100, lacp_rate=fast, xmit_hash_policy=layer3+4)..."
sudo nmcli con add type bond ifname "$BOND" con-name "$BOND" \
  bond.options "mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer3+4"

# Bond gets DHCP IPv4; ignore IPv6 to silence RS warnings; prefer with lower metric
sudo nmcli con mod "$BOND" ipv4.method auto ipv4.route-metric "$BOND_METRIC" ipv6.method ignore

echo "==> Adding X540 ports as slaves (no IP on slaves)..."
sudo nmcli con add type ethernet ifname "$IF_A" master "$BOND" con-name "bond-slave-$IF_A"
sudo nmcli con add type ethernet ifname "$IF_B" master "$BOND" con-name "bond-slave-$IF_B"
# (Slave profiles don't support ipv4.*; NM treats them as bond-ports automatically.)

echo "==> Configuring onboard NIC as independent backup (DHCP, higher metric, no IPv6)..."
# Delete any existing profiles bound to BACKUP_IF, then create clean one
while read -r uuid; do
  [ -n "$uuid" ] && sudo nmcli con delete "$uuid" || true
done < <(nmcli -g UUID,TYPE,DEVICE con show | awk -F: -v d="$BACKUP_IF" '$3==d{print $1}')
sudo nmcli con add type ethernet ifname "$BACKUP_IF" con-name "onboard-eth" \
  ipv4.method auto ipv4.route-metric "$BACKUP_METRIC" ipv6.method ignore

echo "==> Bringing everything up (slaves first, then bond, then backup NIC)..."
sudo nmcli con up "bond-slave-$IF_A"
sudo nmcli con up "bond-slave-$IF_B"
sudo nmcli con up "$BOND"
sudo nmcli con up "onboard-eth"

echo "==> Cleaning stray routes on slaves (if any)..."
sudo ip route del default dev "$IF_A" 2>/dev/null || true
sudo ip route del default dev "$IF_B" 2>/dev/null || true

echo "==> Final status:"
nmcli -f NAME,UUID,TYPE,DEVICE,STATE con show | column -t
echo
ip -4 addr show "$BOND" || true
echo
ip route
echo
cat /proc/net/bonding/"$BOND" || true

echo
echo "✅ Done. bond0 should have a single DHCP IPv4 + default (metric $BOND_METRIC),"
echo "   enp9s0 should be a backup default (metric $BACKUP_METRIC)."
echo "   Both $IF_A and $IF_B should appear as slaves with the SAME Aggregator ID."
