#!/bin/bash

# Get Tailscale status and IP address
echo "Tailscale Status:"
tailscale up --socket /var/run/tailscale/tailscaled.sock 2>/dev/null || true
tailscale status | grep -oE "192.168.1.0/24"

echo ""
echo "Tailscale Node List (Note: 'node list' is not supported):"
tailscale up --socket /var/run/tailscale/tailscaled.sock 2>/dev/null || true
tailscale status

# Get NGINX version and running services
echo ""
echo "NGINX Information:"
nginx -h | head -n 1
nginx -v

# Check if NGINX is running
if systemctl is-active --quiet nginx; then
    echo "NGINX Service Status: Running"
else
    echo "NGINX Service Status: Not Running"
fi

echo ""
echo "Running NGINX Services (List of processes related to NGINX):"
ps aux | grep -E 'nginx|httpd'

# Get Tailscale IP address again for clarity
echo ""
echo "Tailscale IPs:"
tailscale ip

# List running services on the system
echo ""
echo "Running System Services:"
systemctl list-units --type=service --state=running

# Optional: List listening ports (you can use netstat or ss)
echo ""
echo "Listening Ports on Tailscale IP:"
ss -tulwn | grep 192.168.1

# NGINX Configuration Test
if nginx -t; then
    echo "NGINX Configuration is Valid"
else
    echo "NGINX Configuration has Errors, please check the configuration file."
fi

echo ""
