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
