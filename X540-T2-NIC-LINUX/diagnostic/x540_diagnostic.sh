#!/bin/bash

# Intel X540 Diagnostic Script
# Checks link status, routing, and interface health

echo "=== Intel X540 Network Diagnostic ==="
echo

# Step 1: Identify ixgbe interfaces
echo "[1] Detecting ixgbe interfaces..."
mapfile -t IFACES < <(ls /sys/class/net/ | while read iface; do
  if ethtool -i "$iface" 2>/dev/null | grep -q ixgbe; then
    echo "$iface"
  fi
done)

if [ ${#IFACES[@]} -eq 0 ]; then
  echo "❌ No Intel X540 interfaces found with ixgbe driver."
  exit 1
fi

echo "✅ Found ${#IFACES[@]} ixgbe interface(s): ${IFACES[*]}"
echo

# Step 2: Print ethtool status
for IFACE in "${IFACES[@]}"; do
  echo "[2] Interface: $IFACE"
  ethtool "$IFACE" | grep -E 'Speed:|Duplex:|Auto-negotiation:|Link detected:'
  echo

  SPEED=$(ethtool "$IFACE" | grep "Speed" | awk '{print $2}')
  if [[ "$SPEED" != "10000Mb/s" ]]; then
    echo "⚠️  Warning: $IFACE is NOT running at 10Gbps (current: $SPEED)"
    echo "   ➤ Check that you're using Cat6a/Cat7 and a 10GbE switch port."
    echo
  else
    echo "✅ $IFACE is running at 10Gbps."
    echo
  fi
done

# Step 3: Show IP and default route
echo "[3] Default route:"
ip route show | grep '^default' | while read -r line; do
  echo "→ $line"
done
echo

# Step 4: Print IP address info
echo "[4] Interface IP addresses:"
for IFACE in "${IFACES[@]}"; do
  IP=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  if [ -n "$IP" ]; then
    echo "✅ $IFACE has IP: $IP"
  else
    echo "⚠️  $IFACE has no IPv4 address assigned."
  fi
done
echo

# Step 5: Show active egress interface (default route)
EGRESS_IFACE=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'dev \K\S+')
echo "[5] System default egress interface:"
if [ -n "$EGRESS_IFACE" ]; then
  echo "🌐 Default route uses: $EGRESS_IFACE"
else
  echo "⚠️  No egress interface detected for outbound traffic."
fi
echo

echo "=== Diagnostic complete ==="
