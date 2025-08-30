#!/usr/bin/env bash
# Quick "panic button" network recovery for bond0 + enp9s0

set -euo pipefail

IFACES=("bond0" "enp9s0")

echo "[fixnet] Flushing addresses and killing old dhclient…"
for IF in "${IFACES[@]}"; do
    sudo ip addr flush dev "$IF" || true
    sudo pkill -f "dhclient.*$IF" 2>/dev/null || true
done

echo "[fixnet] Requesting fresh DHCP leases…"
sudo dhclient -v "${IFACES[@]}"

echo "[fixnet] Current routes:"
ip route

echo "[fixnet] Current addresses:"
ip -4 addr show bond0
ip -4 addr show enp9s0

echo "[fixnet] Done. Try pinging your gateway:"
echo "  ping -c3 192.168.1.254"
