Below is a distilled “recipe” you can copy-and-paste to reproduce the author’s working Ubuntu-based setup.  
Everything that is **optional** is marked as such; everything else is required.

------------------------------------------------
1.  Prerequisites
------------------------------------------------
• Server motherboard / NIC must support **Wake-on-LAN with unicast packets**  
  (check with `sudo ethtool <iface> | grep -i wake` – you need the flag `u`).

• One **always-on Linux box** on the same L2 segment (Pi, thin-client, etc.).

• You accept disabling IPv6 on the server (ARP is IPv4-only).  
  If you need IPv6, you’ll have to extend the stand-in script for NDP later.

------------------------------------------------
2.  Server side – enable & persist WoL
------------------------------------------------
```bash
IFACE=eno1                         # change to your interface
sudo ethtool -s $IFACE wol ug     # g = magic, u = unicast

# Persist after every link-up (Ubuntu ≥ 20.04 uses networkd-dispatcher)
sudo tee /etc/networkd-dispatcher/configuring.d/wol >/dev/null <<'EOF'
#!/usr/bin/env bash
ethtool -s eno1 wol ug || true
EOF
sudo chmod +x /etc/networkd-dispatcher/configuring.d/wol
```

------------------------------------------------
3.  Server side – auto-suspend on idle
------------------------------------------------
Create the idle-check script:

```bash
SCRIPT_DIR=/home/ubuntu                 # change if you like
cat <<'EOF' > "$SCRIPT_DIR/auto-sleep.sh"
#!/bin/bash
logged_in=$(who | wc -l)
afp_conn=$(lsof -i :548 2>/dev/null | wc -l)   # AFP/Time-Machine
if (( logged_in == 0 )) && (( afp_conn < 3 )); then
    logger "autosuspend: idle, going to sleep"
    systemctl suspend
else
    logger "autosuspend: $logged_in users, AFP=$afp_conn – staying up"
fi
EOF
chmod +x "$SCRIPT_DIR/auto-sleep.sh"
```

Schedule it every 10 min via root’s crontab:

```bash
sudo crontab -l | { cat; echo "*/10 * * * * $SCRIPT_DIR/auto-sleep.sh | logger -t autosuspend"; } | sudo crontab -
```

------------------------------------------------
4.  Server side – disable IPv6 (optional but recommended)
------------------------------------------------
```bash
sudo sed -i '/GRUB_CMDLINE_LINUX=/s/"$/ ipv6.disable=1"/' /etc/default/grub
sudo update-grub
sudo reboot
```

------------------------------------------------
5.  Server side – stop services before sleep (optional)
------------------------------------------------
Example for Netatalk (AFP).  Adjust service names if you use Samba, etc.

```bash
sudo tee /etc/systemd/system/netatalk-sleep.service >/dev/null <<'EOF'
[Unit]
Description=Netatalk sleep hook
Before=sleep.target
StopWhenUnneeded=yes

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=-/usr/bin/systemctl stop netatalk
ExecStop=-/usr/bin/systemctl start netatalk

[Install]
WantedBy=sleep.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable netatalk-sleep.service
```

------------------------------------------------
6.  Always-on device – install ARP stand-in
------------------------------------------------
```bash
# on the Pi / always-on box
sudo apt update
sudo apt install ruby ruby-dev libpcap-dev build-essential
sudo gem install pcaprub
git clone https://github.com/danielpgross/arp_standin.git
cd arp_standin
```

Create the config file `config.yml`:

```yaml
interface: eth0                 # Pi interface facing the LAN
target_ip: 192.168.1.3
target_mac: "aa:bb:cc:dd:ee:ff" # MAC of sleeping server
```

Install as a systemd service:

```bash
sudo cp arp_standin.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now arp_standin
```

------------------------------------------------
7.  Always-on device – mDNS stand-in (Bonjour / Avahi)
------------------------------------------------
Install Avahi:

```bash
sudo apt install avahi-daemon
```

Publish the same AFP service the real server offers:

```bash
sudo tee /etc/systemd/system/avahi-publish.service >/dev/null <<'EOF'
[Unit]
Description=Publish homeserver AFP over mDNS
After=network.target avahi-daemon.service
Requires=avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/bin/avahi-publish -s homeserver _afpovertcp._tcp 548 -H homeserver.local
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now avahi-publish
```

------------------------------------------------
8.  Test
------------------------------------------------
1. From any LAN client: `ping homeserver.local` should resolve and wake the server.  
2. Start a Time-Machine backup; server should wake → finish → idle 10 min → sleep.  
3. While asleep, the Pi should still answer ARP for `192.168.1.3` and mDNS for `homeserver.local`.

------------------------------------------------
9.  Troubleshooting quick list
------------------------------------------------
- Server wakes randomly → capture with a mirrored switch port; look for:
  – AFP packets from macOS (fix with service stop hook)  
  – NetBIOS broadcasts from router (disable or flash firmware)  

- `ethtool` shows no “u” flag → NIC/driver can’t do wake-on-unicast; fallback is magic-packet-only.

- mDNS not working from Mac → `dns-sd -L homeserver _afpovertcp._tcp local` must return the Pi’s IP.  
  If it doesn’t, restart `avahi-daemon` on the Pi and check firewall rules.

That’s it—your home server now behaves like a “proper” appliance: silent, power-sipping, and instantly available when any client needs it.

---
DS
---
Configuring a Linux home server to automatically sleep when idle and wake on demand involves several steps, including setting up sleep triggers, enabling Wake-on-LAN (WoL) features, and ensuring reliable wake-up mechanisms. Below is a structured guide based on the provided search results and best practices.

---

### 🔧 1. **Enable Wake-on-LAN (WoL) for Unicast Packets**
   - The network interface must support WoL with unicast packets (not just magic packets). Use `ethtool` to configure this:
     ```bash
     sudo ethtool -s eno1 wol ug  # Enable WoL for unicast (u) and magic packets (g)
     ```
   - Make this setting persistent across reboots by creating a script in `/etc/networkd-dispatcher/configuring.d/`:
     ```bash
     sudo tee /etc/networkd-dispatcher/configuring.d/wol << EOF
     #!/usr/bin/env bash
     ethtool -s eno1 wol ug || true
     EOF
     sudo chmod 755 /etc/networkd-dispatcher/configuring.d/wol
     ```

---

### ⏸️ 2. **Set Up Sleep on Idle**
   - Create a script (e.g., `/home/ubuntu/auto-sleep.sh`) to check idle conditions (e.g., no logged-in users or active AFP connections for Time Machine backups):
     ```bash
     #!/bin/bash
     logged_in_count=$(who | wc -l)
     afp_connection_count=$(lsof -i:548 | wc -l)
     if [[ $logged_in_count -lt 1 && $afp_connection_count -lt 3 ]]; then
       systemctl suspend
     else
       echo "Not suspending: logged-in users: $logged_in_count, AFP connections: $afp_connection_count"
     fi
     ```
     Make it executable: `chmod +x /home/ubuntu/auto-sleep.sh`.
   - Schedule the script to run periodically via cron:
     ```bash
     sudo crontab -e
     # Add line: */10 * * * * /home/ubuntu/auto-sleep.sh | logger -t autosuspend
     ```

---

### 📵 3. **Disable IPv6 (Optional)**
   - This setup relies on ARP, which IPv6 does not use. Disable IPv6 to prevent issues:
     ```bash
     sudo nano /etc/default/grub
     # Add `ipv6.disable=1` to `GRUB_CMDLINE_LINUX`
     sudo update-grub
     sudo reboot
     ```

---

### 🖥️ 4. **Configure an Always-On Device (e.g., Raspberry Pi)**
   - Use a low-power device to act as an ARP stand-in for the sleeping server. This device will respond to ARP requests on behalf of the server, ensuring other machines can resolve its IP address.
   - Install `avahi-daemon` to advertise network services (e.g., Time Machine) while the server is asleep:
     ```bash
     sudo apt install avahi-daemon
     sudo tee /etc/systemd/system/avahi-publish.service << EOF
     [Unit]
     Description=Publish custom Avahi records
     After=network.target avahi-daemon.service
     Requires=avahi-daemon.service

     [Service]
     ExecStart=/usr/bin/avahi-publish -s homeserver _afpovertcp._tcp 548 -H homeserver.local

     [Install]
     WantedBy=multi-user.target
     EOF
     sudo systemctl enable avahi-publish.service --now
     ```

---

### 💾 5. **Manage Disk Sleep Settings**
   - Use `hdparm` to configure hard drive spindown time for additional power savings:
     ```bash
     sudo hdparm -S 36 /dev/sdb  # Spin down after 36*5 seconds (3 minutes) of inactivity
     ```
   - Make settings persistent via `/etc/hdparm.conf`:
     ```bash
     /dev/disk/by-uuid/your-drive-uuid {
         spindown_time = 36
     }
     ```
   - Debug unwanted disk wake-ups using `auditd` to log access attempts:
     ```bash
     sudo auditctl -w /dev/sda -p rwa  # Log read/write/access events
     ```

---

### ⚠️ 6. **Address Common Caveats**
   - **Unwakeable Server**: If the server becomes unreachable after sleep, ensure the ARP cache on clients does not expire. The always-on device (Raspberry Pi) must respond to ARP requests.
   - **Unwanted Wake-ups**: Stop network services (e.g., Netatalk) before sleep to prevent accidental wake-ups:
     ```bash
     sudo systemctl stop netatalk  # Before sleep
     sudo systemctl start netatalk  # After wake
     ```
   - **BIOS Settings**: Enable WoL in the BIOS/UEFI settings of the server.

---

### 🔍 7. **Troubleshooting Tips**
   - **Test WoL**: Use `wakeonlan` or `etherwake` from another machine to wake the server.
   - **Check Logs**: Use `journalctl` or syslog to monitor sleep/wake events.
   - **Driver Support**: Ensure the network driver supports WoL with unicast packets (e.g., Intel I219-LM may require driver tweaks).

---

### 💎 Conclusion
This configuration allows a Linux home server to sleep when idle and wake on demand, saving power without sacrificing accessibility. Key components include:
- WoL with unicast support.
- An always-on device to handle ARP requests.
- Careful management of network services and disk sleep settings.

For more details, refer to the original guide and supplementary discussions.
