Configuring a Linux home server to automatically sleep when idle and wake on demand involves several key steps, including enabling wake-on-LAN (WoL) features, setting up sleep triggers, and ensuring reliable wake-up mechanisms. Below is a structured guide based on the provided search results and best practices.

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
   - Install `friendly-neighbor` (a lightweight service that responds to ARP/NDP requests) via Snap:
     ```bash
     sudo snap install friendly-neighbor
     sudo snap connect friendly-neighbor:hardware-observe
     sudo snap connect friendly-neighbor:network-control
     sudo snap set friendly-neighbor mac-ip-mappings="AA:BB:CC:DD:EE:FF,10.0.1.2" interface-name=eth0
     sudo snap restart friendly-neighbor
     ```
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
     sudo systemctl daemon-reload
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
     sudo tee /etc/systemd/system/netatalk-sleep.service << EOF
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
