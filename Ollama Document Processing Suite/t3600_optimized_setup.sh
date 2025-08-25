#!/bin/bash

# T3600 Optimized Ollama Document Processing Setup
# Specifically optimized for Dell Precision T3600 with dual GPUs
# Ubuntu 24.04.3 LTS, Intel Xeon E5-1660, GTX 1060 6GB + Quadro P4000

set -euo pipefail

# T3600 System Configuration
XEON_CORES=12  # E5-1660 has 6 cores, 12 threads
GTX_1060_VRAM=6  # GTX 1060 6GB
QUADRO_P4000_VRAM=8  # Quadro P4000 8GB
TOTAL_RAM=64  # 64GB system RAM

# Optimized settings for this hardware
OLLAMA_NUM_PARALLEL=4
OLLAMA_MAX_LOADED_MODELS=2
OLLAMA_FLASH_ATTENTION=1

echo "=== T3600 Ollama Optimization Setup ==="
echo "System: Dell Precision T3600"
echo "CPU: Intel Xeon E5-1660 (6C/12T @ 3.9GHz)"
echo "RAM: 64GB"
echo "GPU1: NVIDIA GTX 1060 6GB"
echo "GPU2: NVIDIA Quadro P4000 8GB"
echo

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check T3600 specific hardware
check_t3600_hardware() {
    log "Verifying T3600 hardware configuration..."
    
    # Check CPU
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    if [[ "$CPU_MODEL" == *"E5-1660"* ]]; then
        success "Detected correct CPU: $CPU_MODEL"
    else
        warning "CPU model doesn't match E5-1660: $CPU_MODEL"
    fi
    
    # Check RAM
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM_GB" -ge 60 ]; then
        success "Sufficient RAM detected: ${TOTAL_RAM_GB}GB"
    else
        warning "RAM may be insufficient: ${TOTAL_RAM_GB}GB (recommended: 64GB)"
    fi
    
    # Check GPUs
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
        success "Detected $GPU_COUNT NVIDIA GPU(s)"
        
        # Show GPU details
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits | while read gpu; do
            log "GPU: $gpu"
        done
    else
        error "NVIDIA drivers not detected. Please install CUDA drivers first."
        exit 1
    fi
}

# Install T3600 optimized CUDA/drivers
install_cuda_drivers() {
    log "Installing optimized CUDA drivers for T3600..."
    
    # Add NVIDIA package repository
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt-get update
    
    # Install CUDA toolkit and drivers
    sudo apt-get install -y cuda-drivers cuda-toolkit-12-4
    
    # Install additional libraries
    sudo apt-get install -y nvidia-cuda-toolkit nvidia-utils-535
    
    success "CUDA drivers installed"
}

# Configure environment for dual GPU setup
configure_dual_gpu() {
    log "Configuring dual GPU environment..."
    
    # Create systemd service for optimal GPU settings
    sudo tee /etc/systemd/system/ollama-gpu-optimization.service > /dev/null << 'EOF'
[Unit]
Description=Ollama GPU Optimization for T3600
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'nvidia-smi -pm 1; nvidia-smi -pl 200'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl enable ollama-gpu-optimization.service
    
    # Set environment variables for optimal performance
    cat >> ~/.bashrc << EOF

# T3600 Ollama Optimization
export OLLAMA_NUM_PARALLEL=4
export OLLAMA_MAX_LOADED_MODELS=2
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_ORIGINS=*
export CUDA_VISIBLE_DEVICES=0,1
EOF
    
    success "Dual GPU configuration applied"
}

# Create optimized model recommendations
create_model_config() {
    log "Creating T3600-optimized model configuration..."
    
    cat > t3600_models.conf << 'EOF'
# T3600 Optimized Model Configuration
# Based on GTX 1060 6GB + Quadro P4000 8GB setup

[small_models]  # For GTX 1060 6GB
llama3.2_3b = "llama3.2:3b"          # ~2.5GB VRAM
phi3_mini = "phi3:mini"               # ~2.3GB VRAM
gemma2_2b = "gemma2:2b"              # ~1.8GB VRAM
qwen2.5_3b = "qwen2.5:3b"            # ~2.6GB VRAM

[medium_models]  # For Quadro P4000 8GB
llama3.2_8b = "llama3.2:8b"          # ~5.5GB VRAM
codellama_7b = "codellama:7b"         # ~4.8GB VRAM
qwen2.5_7b = "qwen2.5:7b"            # ~5.2GB VRAM
mistral_7b = "mistral:7b"             # ~4.9GB VRAM

[vision_models]  # For document OCR
llama3.2_vision_11b = "llama3.2-vision:11b"  # Requires both GPUs
minicpm_v = "minicpm-v:latest"        # ~6GB VRAM

[embedding_models]
nomic_embed = "nomic-embed-text"      # ~500MB VRAM
all_minilm = "all-minilm:latest"      # ~400MB VRAM

[recommended_combinations]
# GPU 0 (GTX 1060): Small model for fast processing
# GPU 1 (Quadro P4000): Medium model for complex tasks
dual_gpu_setup = ["llama3.2:3b", "qwen2.5:7b"]
EOF
    
    success "Model configuration created: t3600_models.conf"
}

# Install and configure optimized Ollama
install_optimized_ollama() {
    log "Installing Ollama with T3600 optimizations..."
    
    # Download and install Ollama
    curl -fsSL https://ollama.ai/install.sh | sh
    
    # Create custom Ollama configuration
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_NUM_PARALLEL=4"
Environment="OLLAMA_MAX_LOADED_MODELS=2"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="CUDA_VISIBLE_DEVICES=0,1"
EOF
    
    # Reload systemd and restart Ollama
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    sudo systemctl enable ollama
    
    success "Ollama installed and optimized"
}

# Pull recommended models for T3600
pull_recommended_models() {
    log "Pulling recommended models for T3600..."
    
    # Small models for GTX 1060
    ollama pull llama3.2:3b
    ollama pull phi3:mini  
    ollama pull gemma2:2b
    
    # Medium models for Quadro P4000
    ollama pull qwen2.5:7b
    ollama pull codellama:7b
    
    # Vision model for OCR
    ollama pull llama3.2-vision:11b
    
    # Embedding model
    ollama pull nomic-embed-text
    
    success "Recommended models installed"
}

# Create dual GPU launcher scripts
create_dual_gpu_launchers() {
    log "Creating dual GPU launcher scripts..."
    
    # GTX 1060 launcher (GPU 0)
    cat > start_ollama_gtx1060.sh << 'EOF'
#!/bin/bash
# Launch Ollama on GTX 1060 (GPU 0) - Port 11434
export CUDA_VISIBLE_DEVICES=0
export OLLAMA_HOST=0.0.0.0:11434
export OLLAMA_MAX_LOADED_MODELS=1

echo "Starting Ollama on GTX 1060 (GPU 0) - Port 11434"
ollama serve > ollama_gtx1060.log 2>&1 &
echo $! > ollama_gtx1060.pid
EOF
    
    # Quadro P4000 launcher (GPU 1)  
    cat > start_ollama_quadro.sh << 'EOF'
#!/bin/bash
# Launch Ollama on Quadro P4000 (GPU 1) - Port 11435
export CUDA_VISIBLE_DEVICES=1
export OLLAMA_HOST=0.0.0.0:11435
export OLLAMA_MAX_LOADED_MODELS=1

echo "Starting Ollama on Quadro P4000 (GPU 1) - Port 11435"
ollama serve > ollama_quadro.log 2>&1 &
echo $! > ollama_quadro.pid
EOF
    
    # Combined launcher
    cat > start_dual_gpu.sh << 'EOF'
#!/bin/bash
# Start both GPU servers for maximum performance

echo "=== T3600 Dual GPU Ollama Startup ==="
echo "Starting Ollama on both GPUs..."

./start_ollama_gtx1060.sh
sleep 3
./start_ollama_quadro.sh
sleep 3

echo "Both servers started:"
echo "  GTX 1060:     http://localhost:11434"
echo "  Quadro P4000: http://localhost:11435"

# Test both servers
curl -s http://localhost:11434/api/tags > /dev/null && echo "✓ GTX 1060 server ready" || echo "✗ GTX 1060 server failed"
curl -s http://localhost:11435/api/tags > /dev/null && echo "✓ Quadro P4000 server ready" || echo "✗ Quadro P4000 server failed"
EOF
    
    # Stop script
    cat > stop_dual_gpu.sh << 'EOF'
#!/bin/bash
# Stop both GPU servers

echo "Stopping dual GPU servers..."

if [ -f ollama_gtx1060.pid ]; then
    kill $(cat ollama_gtx1060.pid) 2>/dev/null && echo "✓ GTX 1060 server stopped"
    rm -f ollama_gtx1060.pid
fi

if [ -f ollama_quadro.pid ]; then
    kill $(cat ollama_quadro.pid) 2>/dev/null && echo "✓ Quadro P4000 server stopped" 
    rm -f ollama_quadro.pid
fi

echo "All servers stopped"
EOF
    
    chmod +x start_ollama_*.sh start_dual_gpu.sh stop_dual_gpu.sh
    success "Dual GPU launchers created"
}

# Create T3600-optimized document processor
create_t3600_processor() {
    log "Creating T3600-optimized document processor..."
    
    cat > t3600_document_processor.py << 'EOF'
#!/usr/bin/env python3
"""
T3600 Optimized Document Processor
Leverages both GTX 1060 and Quadro P4000 for maximum performance
"""

import asyncio
import time
import json
from pathlib import Path
from typing import List, Dict, Any
import aiohttp
import aiofiles
from concurrent.futures import ThreadPoolExecutor
import argparse

class T3600DocumentProcessor:
    def __init__(self):
        # T3600 GPU configuration
        self.gpu_configs = {
            'gtx1060': {
                'url': 'http://localhost:11434',
                'model': 'llama3.2:3b',  # Fast model for GTX 1060
                'max_concurrent': 2
            },
            'quadro': {
                'url': 'http://localhost:11435', 
                'model': 'qwen2.5:7b',   # More powerful model for P4000
                'max_concurrent': 2
            }
        }
        
        self.session = None
        
    async def __aenter__(self):
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=300))
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    async def process_with_gpu(self, gpu_name: str, prompt: str, content: str) -> Dict[str, Any]:
        """Process document content with specific GPU"""
        config = self.gpu_configs[gpu_name]
        
        payload = {
            "model": config['model'],
            "prompt": f"{prompt}\n\nDocument content:\n{content}",
            "stream": False
        }
        
        start_time = time.time()
        
        try:
            async with self.session.post(f"{config['url']}/api/generate", json=payload) as response:
                if response.status == 200:
                    result = await response.json()
                    return {
                        'gpu': gpu_name,
                        'model': config['model'],
                        'response': result['response'],
                        'processing_time': time.time() - start_time,
                        'success': True
                    }
                else:
                    return {
                        'gpu': gpu_name,
                        'error': f"HTTP {response.status}",
                        'processing_time': time.time() - start_time,
                        'success': False
                    }
        except Exception as e:
            return {
                'gpu': gpu_name,
                'error': str(e),
                'processing_time': time.time() - start_time,
                'success': False
            }
    
    async def process_document_dual_gpu(self, file_path: Path, prompt: str) -> Dict[str, Any]:
        """Process document using both GPUs for comparison/redundancy"""
        
        # Read document content
        async with aiofiles.open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = await f.read()
        
        # Process with both GPUs simultaneously
        tasks = [
            self.process_with_gpu('gtx1060', prompt, content[:4000]),  # GTX 1060: smaller chunk
            self.process_with_gpu('quadro', prompt, content[:6000])    # P4000: larger chunk
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        return {
            'file': str(file_path),
            'results': {
                'gtx1060': results[0] if not isinstance(results[0], Exception) else {'error': str(results[0]), 'success': False},
                'quadro': results[1] if not isinstance(results[1], Exception) else {'error': str(results[1]), 'success': False}
            }
        }
    
    async def process_directory(self, source_dir: Path, target_dir: Path, prompt: str):
        """Process all documents in directory using dual GPU setup"""
        
        source_dir = Path(source_dir)
        target_dir = Path(target_dir) 
        target_dir.mkdir(parents=True, exist_ok=True)
        
        # Find all text files
        files = []
        for ext in ['.txt', '.md', '.py', '.js', '.html', '.json']:
            files.extend(source_dir.rglob(f'*{ext}'))
        
        print(f"Processing {len(files)} files with dual GPU setup...")
        
        # Process files with controlled concurrency
        semaphore = asyncio.Semaphore(4)  # Limit concurrent operations
        
        async def process_with_semaphore(file_path):
            async with semaphore:
                return await self.process_document_dual_gpu(file_path, prompt)
        
        # Process all files
        tasks = [process_with_semaphore(file_path) for file_path in files]
        results = await asyncio.gather(*tasks)
        
        # Save results
        for result in results:
            file_path = Path(result['file'])
            output_file = target_dir / f"{file_path.stem}_dual_gpu.json"
            
            async with aiofiles.open(output_file, 'w') as f:
                await f.write(json.dumps(result, indent=2))
        
        # Create summary
        summary = {
            'total_files': len(files),
            'gpu_performance': {
                'gtx1060': {
                    'successful': sum(1 for r in results if r['results']['gtx1060']['success']),
                    'avg_time': sum(r['results']['gtx1060'].get('processing_time', 0) for r in results) / len(results)
                },
                'quadro': {
                    'successful': sum(1 for r in results if r['results']['quadro']['success']),
                    'avg_time': sum(r['results']['quadro'].get('processing_time', 0) for r in results) / len(results)
                }
            }
        }
        
        summary_file = target_dir / 'dual_gpu_summary.json'
        async with aiofiles.open(summary_file, 'w') as f:
            await f.write(json.dumps(summary, indent=2))
        
        print(f"Processing complete! Results saved to {target_dir}")
        print(f"Summary: {summary}")

async def main():
    parser = argparse.ArgumentParser(description="T3600 Dual GPU Document Processor")
    parser.add_argument('source_dir', help="Source directory")
    parser.add_argument('target_dir', help="Target directory")
    parser.add_argument('--prompt', required=True, help="Processing prompt")
    
    args = parser.parse_args()
    
    async with T3600DocumentProcessor() as processor:
        await processor.process_directory(args.source_dir, args.target_dir, args.prompt)

if __name__ == "__main__":
    asyncio.run(main())
EOF
    
    chmod +x t3600_document_processor.py
    success "T3600 document processor created"
}

# Create performance monitoring script
create_performance_monitor() {
    log "Creating T3600 performance monitoring script..."
    
    cat > monitor_t3600.sh << 'EOF'
#!/bin/bash

# T3600 Performance Monitor for Ollama

echo "=== T3600 Performance Monitor ==="
echo "Monitoring system performance during Ollama operations"
echo

while true; do
    clear
    echo "=== T3600 System Status - $(date) ==="
    echo
    
    # CPU Usage
    echo "CPU Usage (Xeon E5-1660):"
    echo "  $(top -bn1 | grep "Cpu(s)" | awk '{print $2 $3 $4 $5 $6 $7 $8}')"
    echo
    
    # Memory Usage  
    echo "Memory Usage (64GB total):"
    free -h | grep -E "Mem|Swap"
    echo
    
    # GPU Status
    echo "GPU Status:"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits | while read line; do
            echo "  $line"
        done
    else
        echo "  NVIDIA-SMI not available"
    fi
    echo
    
    # Ollama Process Status
    echo "Ollama Processes:"
    ps aux | grep ollama | grep -v grep | while read line; do
        echo "  $line" | awk '{print $2, $3"%", $4"%", $11}'
    done
    echo
    
    # Network connections (Ollama API ports)
    echo "Active Connections:"
    netstat -tulpn | grep -E ":(11434|11435)" | while read line; do
        echo "  $line"
    done
    echo
    
    sleep 5
done
EOF
    
    chmod +x monitor_t3600.sh
    success "Performance monitor created"
}

# Create comprehensive setup script
create_setup_all() {
    log "Creating comprehensive T3600 setup script..."
    
    cat > setup_t3600_complete.sh << 'EOF'
#!/bin/bash

# Complete T3600 Setup for Ollama Document Processing

echo "=== Complete T3600 Ollama Setup ==="
echo "This will install and configure everything needed for optimal performance"
echo

read -p "Continue with complete setup? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi

# Update system
echo "Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Install essential packages
sudo apt-get install -y \
    python3-pip python3-venv python3-dev \
    build-essential cmake git curl wget \
    htop nvtop iotop \
    magic-wand imagemagick tesseract-ocr \
    pandoc poppler-utils \
    nodejs npm

# Install Python packages for document processing
pip3 install --user \
    aiohttp aiofiles \
    ollama python-docx pypdf2 \
    python-magic beautifulsoup4 \
    pandas numpy \
    langchain langchain-community \
    click tqdm

echo "✓ Essential packages installed"

# Setup CUDA (if not already installed)
if ! command -v nvcc &> /dev/null; then
    echo "Installing CUDA toolkit..."
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt-get update
    sudo apt-get install -y cuda-toolkit-12-4
    echo "✓ CUDA toolkit installed"
fi

# Install Ollama
if ! command -v ollama &> /dev/null; then
    echo "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    echo "✓ Ollama installed"
fi

# Configure system for dual GPU
echo "Configuring dual GPU setup..."
# Add current user to render group for GPU access
sudo usermod -a -G render $USER

# Set GPU performance mode
sudo nvidia-smi -pm 1
sudo nvidia-smi -pl 200  # Set power limit to 200W

echo "✓ System configured for T3600"

# Create project directory structure
mkdir -p ~/ollama-t3600/{documents/{input,output},scripts,models,logs}
cd ~/ollama-t3600

echo "✓ Project structure created at ~/ollama-t3600"

echo
echo "=== Setup Complete ==="
echo "Please reboot your system to ensure all changes take effect."
echo "After reboot, run the dual GPU launcher scripts."
EOF
    
    chmod +x setup_t3600_complete.sh
    success "Complete setup script created"
}

# Main menu for T3600 setup
show_t3600_menu() {
    echo
    echo "=== T3600 Ollama Setup Menu ==="
    echo "1. Check T3600 hardware"
    echo "2. Install/configure CUDA drivers"
    echo "3. Install optimized Ollama"
    echo "4. Configure dual GPU setup"
    echo "5. Pull recommended models"
    echo "6. Create launcher scripts"
    echo "7. Create document processor"
    echo "8. Create performance monitor"
    echo "9. Complete automated setup"
    echo "10. Test dual GPU performance"
    echo "11. Exit"
    echo
}

# Test dual GPU performance
test_dual_gpu_performance() {
    log "Testing dual GPU performance..."
    
    # Create test prompt
    TEST_PROMPT="Analyze this text and provide a summary with key points."
    TEST_TEXT="This is a test document for performance evaluation of the T3600 dual GPU setup. The system includes an Intel Xeon E5-1660 processor with 12 threads, 64GB of RAM, and two NVIDIA GPUs: a GTX 1060 6GB and a Quadro P4000 8GB. This configuration allows for efficient parallel processing of documents using different models on each GPU."
    
    # Test GTX 1060
    echo "Testing GTX 1060 (Port 11434)..."
    time curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"llama3.2:3b\", \"prompt\": \"$TEST_PROMPT\\n\\n$TEST_TEXT\", \"stream\": false}" \
        | jq -r '.response' | head -3
    
    echo
    
    # Test Quadro P4000
    echo "Testing Quadro P4000 (Port 11435)..."
    time curl -s -X POST http://localhost:11435/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"qwen2.5:7b\", \"prompt\": \"$TEST_PROMPT\\n\\n$TEST_TEXT\", \"stream\": false}" \
        | jq -r '.response' | head -3
    
    success "Performance test completed"
}

# Main execution
main() {
    while true; do
        show_t3600_menu
        read -p "Choose an option: " choice
        
        case $choice in
            1) check_t3600_hardware ;;
            2) install_cuda_drivers ;;
            3) install_optimized_ollama ;;
            4) configure_dual_gpu ;;
            5) pull_recommended_models ;;
            6) create_dual_gpu_launchers ;;
            7) create_t3600_processor ;;
            8) create_performance_monitor ;;
            9) create_setup_all ;;
            10) test_dual_gpu_performance ;;
            11) 
                success "T3600 setup complete!"
                exit 0
                ;;
            *)
                warning "Invalid option. Please try again."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
