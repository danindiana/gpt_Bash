Here’s a **Bash script** that automatically detects the required details (`username`, `working directory`, `Ollama binary path`) and generates a proper `systemd` service file for **Ollama** on **Ubuntu 22.04**:

### **Script: `generate_ollama_service.sh`**
```bash
#!/bin/bash

# Detect the current username
USERNAME=$(whoami)

# Detect the Ollama binary path (default: /usr/local/bin/ollama)
OLLAMA_BIN=$(which ollama || echo "/usr/local/bin/ollama")

# Detect the user's home directory (working directory)
WORKING_DIR=$(eval echo ~$USERNAME)

# Define the systemd service file path
SERVICE_FILE="/etc/systemd/system/ollama.service"

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "❌ Error: Ollama is not installed or not in PATH."
    echo "Install it first: https://ollama.ai"
    exit 1
fi

# Generate the systemd service file
echo "✅ Generating systemd service file at: $SERVICE_FILE"
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Ollama Service
After=network.target

[Service]
ExecStart=$OLLAMA_BIN serve
Restart=always
User=$USERNAME
Group=$USERNAME
WorkingDirectory=$WORKING_DIR
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
echo "🔄 Reloading systemd and enabling Ollama service..."
sudo systemctl daemon-reload
sudo systemctl enable ollama.service
sudo systemctl start ollama.service

# Check status
echo "📊 Checking service status..."
sleep 2  # Give it a moment to start
systemctl status ollama.service --no-pager

echo "🎉 Done! Ollama will now start on boot."
```

---

### **How to Use This Script**
1. **Save it** (e.g., `generate_ollama_service.sh`):
   ```bash
   nano generate_ollama_service.sh
   ```
   (Paste the script, then save with `Ctrl+O`, `Enter`, `Ctrl+X`.)

2. **Make it executable**:
   ```bash
   chmod +x generate_ollama_service.sh
   ```

3. **Run it with sudo** (requires admin privileges):
   ```bash
   sudo ./generate_ollama_service.sh
   ```

---

### **What This Script Does**
1. **Detects:**
   - Current username (`whoami`).
   - Ollama binary path (`which ollama`).
   - User’s home directory (`~$USERNAME`).

2. **Creates the systemd service file** at `/etc/systemd/system/ollama.service`.

3. **Reloads systemd**, enables, and starts the service.

4. **Checks status** to confirm it’s running.

5. **Prints success** once done.

---

### **Verification After Running**
- Check logs:
  ```bash
  journalctl -u ollama.service -b
  ```
- Test reboot:
  ```bash
  sudo reboot
  ```
- Verify it’s running after reboot:
  ```bash
  systemctl status ollama.service
  ```

This script ensures **Ollama starts automatically at boot** without manual configuration! 🚀
