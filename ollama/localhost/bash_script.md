Here's a bash script that automates the process of discovering and setting up Ollama on Ubuntu Linux, including checking system details, exposing it to the network, and configuring environment variables. Make sure you have sudo privileges to run this script.

```bash
#!/bin/bash

# Update package list and install required dependencies
sudo apt update -y
sudo apt install -y curl wget git net-tools

# Check GPU support
GPU_TYPE=$(lspci | grep -i 'vga\|3d\|gpu' | cut -d: -f1)
if [[ $GPU_TYPE == *"nvidia"* ]]; then
  echo "NVIDIA GPU detected. Installing ROCm for GPU acceleration."
  wget https://repo.radeon.com/rocm/apt/debian/rocm.gpg.key -O - | sudo apt-key add -
  echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/debian/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/rocm.list
  sudo apt update -y
  sudo apt install -y rocm
elif [[ $GPU_TYPE == *"amd"* ]]; then
  echo "AMD GPU detected. ROCm is already installed."
else
  echo "No GPU support detected. Ollama will run on CPU only."
fi

# Check available RAM and set Ollama memory limit
MEM_TOTAL=$(free -m | awk '/Mem/ {print $2}')
if [[ $MEM_TOTAL -gt 16384 ]]; then
  OLLAMA_MEM_LIMIT="16GB"
else
  OLLAMA_MEM_LIMIT="50%"
fi

# Set Ollama host and port for network exposure
read -p "Enter the hostname or IP address to expose Ollama (default: localhost): " OLLAMA_HOST
if [[ -z "$OLLAMA_HOST" ]]; then
  OLLAMA_HOST="localhost"
fi
OLLAMA_PORT="11434"

# Install Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Configure Ollama environment variables
echo "Configuring Ollama environment variables..."
cat > /etc/environment <<EOL
OLLAMA_HOST=$OLLAMA_HOST
OLLAMA_PORT=$OLLAMA_PORT
OLLAMA_MEM_LIMIT=$OLLAMA_MEM_LIMIT
EOL

# Set up firewall to allow incoming connections on the specified port (if UFW is installed)
if command -v ufw &> /dev/null; then
  echo "Setting up firewall..."
  sudo ufw allow $OLLAMA_PORT/tcp
fi

echo "Ollama installation and configuration complete. You can now start Ollama using 'ollama run <model>'."

# Start Ollama service (if systemd is installed)
if command -v systemctl &> /dev/null; then
  echo "Starting Ollama service..."
  sudo systemctl start ollama
  sudo systemctl enable ollama
fi
```

Save this script as `setup_ollama.sh` and make it executable with `chmod +x setup_ollama.sh`. Run the script using `sudo ./setup_ollama.sh`.

This script will:

1. Update the package list and install required dependencies.
2. Check for GPU support and install ROCm if an NVIDIA GPU is detected.
3. Determine the available RAM and set an appropriate memory limit for Ollama.
4. Prompt you to enter a hostname or IP address to expose Ollama (default: localhost).
5. Install Ollama using the official installation script.
6. Configure environment variables for Ollama, including host, port, and memory limit.
7. Set up the firewall to allow incoming connections on the specified port (if UFW is installed).
8. Start the Ollama service and enable it to start on boot (if systemd is installed).
