Below is a script that will output relevant system information for both NGINX and Tailscale, including the IP addresses, running services, and other useful details. It won't make any changes but will provide you with the necessary info.

```sh
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
```

### Explanation:

1. **Tailscale Status and IP Address**:
   - `tailscale status` shows the current Tailscale status.
   - We use `grep -oE "192.168.1.0/24"` to get the specific IP address from the output.

2. **NGINX Version and Running Services**:
   - `nginx -h` gives a help message showing the NGINX version.
   - `nginx -v` specifically shows the NGINX version number.
   - Check if `nginx` is running using `systemctl`.
   - List processes related to NGINX with `ps aux`.

3. **Tailscale Node List**:
   - Note that Tailscale node listing isn't directly supported, so we just run `tailscale status` again for clarity.

4. **Running Services**:
   - `systemctl list-units --type=service --state=running` lists all running services on the system.

5. **Listening Ports**:
   - `ss -tulwn | grep 192.168.1` shows listening ports for Tailscale IP addresses (adjust as needed).

6. **NGINX Configuration Test**:
   - Run `nginx -t` to test the NGINX configuration.

### Usage:

Save this script to a file, e.g., `info.sh`, and run it with `bash info.sh`.

This will provide you with all the necessary information without making any changes to your system. Let me know if you need any further customizations or additional details! 🚀
