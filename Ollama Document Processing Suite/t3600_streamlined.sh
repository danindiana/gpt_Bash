#!/bin/bash

# Ollama Document Processor for Existing T3600 Setup
# Leverages your existing Ollama 0.11.4 installation with dual GPUs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/processing.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }

# Check existing setup
check_existing_setup() {
    log "Checking existing T3600 setup..."
    
    # Verify Ollama
    if command -v ollama &> /dev/null; then
        OLLAMA_VERSION=$(ollama -v | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
        success "Ollama $OLLAMA_VERSION detected"
        
        # Show available models optimized for your GPUs
        echo "Available models for T3600 dual GPU setup:"
        ollama list | while read line; do
            if echo "$line" | grep -E "(qwen3:8b|mistral-nemo:12b|phi4|hermes3:8b)" > /dev/null; then
                echo -e "${GREEN}  ✓ $line${NC} (Optimized for P4000)"
            elif echo "$line" | grep -E "(phi-4-mini|EXAONE.*7.8B)" > /dev/null; then
                echo -e "${BLUE}  ○ $line${NC} (Good for GTX 1060)"
            else
                echo -e "${YELLOW}  - $line${NC}"
            fi
        done
    else
        error "Ollama not found in PATH"
        exit 1
    fi
    
    # Check CUDA
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
        success "CUDA detected with $GPU_COUNT GPUs"
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    else
        error "NVIDIA drivers not detected"
        exit 1
    fi
    
    # Check Python
    PYTHON_VERSION=$(python3 --version | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
    success "Python $PYTHON_VERSION detected"
}

# Setup minimal Python dependencies
setup_python_deps() {
    log "Installing required Python packages..."
    
    # Create requirements for document processing
    cat > "${SCRIPT_DIR}/requirements.txt" << EOF
# Minimal requirements for document processing
aiohttp>=3.9.0
aiofiles>=23.0.0
python-docx>=1.1.0
pypdf2>=3.0.0
python-magic>=0.4.27
beautifulsoup4>=4.12.0
click>=8.1.0
tqdm>=4.66.0
pandas>=2.1.0
pillow>=10.0.0
requests>=2.31.0
toml>=0.10.2
EOF
    
    # Install packages
    python3 -m pip install --user -r "${SCRIPT_DIR}/requirements.txt"
    
    success "Python dependencies installed"
}

# Create optimized configuration for your models
create_model_config() {
    log "Creating T3600 model configuration based on your models..."
    
    cat > "${SCRIPT_DIR}/t3600_models.toml" << EOF
# T3600 Model Configuration
# Based on your existing models and GPU capabilities

[gpu_assignments]
# GTX 1060 6GB - Smaller, faster models
gtx1060_models = [
    "ingu627/phi-4-mini-instruct-q4:latest",  # 2.5GB - Perfect for GTX 1060
    "ingu627/EXAONE-Deep-7.8B:latest",        # 4.8GB - Will fit on GTX 1060
    "hermes3:8b"                               # 4.7GB - Good performance
]

# Quadro P4000 8GB - Larger, more capable models  
quadro_models = [
    "qwen3:8b",                                # 5.2GB - Excellent for complex tasks
    "mistral-nemo:12b",                        # 7.1GB - Advanced reasoning
    "mannix/smaug-llama3-8b:q8_0"             # 8.5GB - High quality responses
]

# For very large models that need both GPUs
large_models = [
    "mistral-nemo:12b-instruct-2407-q8_0",    # 13GB - Use with offloading
    "phi4-reasoning:14b",                      # 11GB - Advanced reasoning
    "qwen3-coder:30b"                          # 18GB - Code analysis (offloaded)
]

[processing_configs]
# Fast processing (GTX 1060)
fast = {
    model = "ingu627/phi-4-mini-instruct-q4:latest",
    gpu = 0,
    port = 11434,
    batch_size = 5,
    max_tokens = 2048
}

# Balanced processing (Hermes3 on GTX 1060)
balanced = {
    model = "hermes3:8b", 
    gpu = 0,
    port = 11434,
    batch_size = 3,
    max_tokens = 4096
}

# High quality (Qwen3 on P4000)
quality = {
    model = "qwen3:8b",
    gpu = 1, 
    port = 11435,
    batch_size = 2,
    max_tokens = 8192
}

# Code analysis (Qwen3-coder)
coding = {
    model = "qwen3-coder:30b",
    gpu = 1,
    port = 11435, 
    batch_size = 1,
    max_tokens = 16384,
    context_length = 32768
}

# Advanced reasoning (Phi4 reasoning)
reasoning = {
    model = "phi4-reasoning:14b",
    gpu = 1,
    port = 11435,
    batch_size = 1, 
    max_tokens = 8192
}

[document_types]
# Map document types to optimal models
code_files = ["coding", "quality"]
technical_docs = ["quality", "reasoning"] 
general_text = ["balanced", "fast"]
large_documents = ["quality", "reasoning"]
EOF
    
    success "Model configuration created: t3600_models.toml"
}

# Create dual GPU server manager for your setup
create_gpu_server_manager() {
    log "Creating GPU server manager..."
    
    cat > "${SCRIPT_DIR}/manage_gpu_servers.sh" << 'EOF'
#!/bin/bash

# GPU Server Manager for T3600 Dual Setup
# Manages Ollama instances on GTX 1060 and Quadro P4000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

start_servers() {
    echo "Starting T3600 dual GPU Ollama servers..."
    
    # Stop any existing servers first
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 2
    
    # Start GTX 1060 server (GPU 0, Port 11434)
    echo "Starting GTX 1060 server (GPU 0, Port 11434)..."
    CUDA_VISIBLE_DEVICES=0 OLLAMA_HOST=0.0.0.0:11434 ollama serve > "${SCRIPT_DIR}/ollama_gtx1060.log" 2>&1 &
    GTX_PID=$!
    echo $GTX_PID > "${SCRIPT_DIR}/ollama_gtx1060.pid"
    
    # Start Quadro P4000 server (GPU 1, Port 11435)  
    echo "Starting Quadro P4000 server (GPU 1, Port 11435)..."
    CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST=0.0.0.0:11435 ollama serve > "${SCRIPT_DIR}/ollama_quadro.log" 2>&1 &
    QUADRO_PID=$!
    echo $QUADRO_PID > "${SCRIPT_DIR}/ollama_quadro.pid"
    
    sleep 3
    
    # Test servers
    echo "Testing server connectivity..."
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "✓ GTX 1060 server (port 11434) - Ready"
    else
        echo "✗ GTX 1060 server failed to start"
    fi
    
    if curl -s http://localhost:11435/api/tags > /dev/null; then
        echo "✓ Quadro P4000 server (port 11435) - Ready"
    else 
        echo "✗ Quadro P4000 server failed to start"
    fi
    
    echo "Dual GPU servers started successfully!"
    echo "  GTX 1060:     http://localhost:11434"
    echo "  Quadro P4000: http://localhost:11435"
}

stop_servers() {
    echo "Stopping dual GPU servers..."
    
    if [ -f "${SCRIPT_DIR}/ollama_gtx1060.pid" ]; then
        kill $(cat "${SCRIPT_DIR}/ollama_gtx1060.pid") 2>/dev/null && echo "✓ GTX 1060 server stopped"
        rm -f "${SCRIPT_DIR}/ollama_gtx1060.pid"
    fi
    
    if [ -f "${SCRIPT_DIR}/ollama_quadro.pid" ]; then
        kill $(cat "${SCRIPT_DIR}/ollama_quadro.pid") 2>/dev/null && echo "✓ Quadro P4000 server stopped"
        rm -f "${SCRIPT_DIR}/ollama_quadro.pid" 
    fi
    
    # Kill any remaining ollama processes
    pkill -f "ollama serve" 2>/dev/null || true
    
    echo "All servers stopped"
}

status() {
    echo "T3600 GPU Server Status:"
    echo
    
    # Check processes
    if [ -f "${SCRIPT_DIR}/ollama_gtx1060.pid" ]; then
        GTX_PID=$(cat "${SCRIPT_DIR}/ollama_gtx1060.pid")
        if ps -p $GTX_PID > /dev/null 2>&1; then
            echo "✓ GTX 1060 Server: Running (PID: $GTX_PID)"
            curl -s http://localhost:11434/api/tags > /dev/null && echo "  → API: Responsive" || echo "  → API: Not responding"
        else
            echo "✗ GTX 1060 Server: Not running"
        fi
    else
        echo "✗ GTX 1060 Server: Not running"
    fi
    
    if [ -f "${SCRIPT_DIR}/ollama_quadro.pid" ]; then
        QUADRO_PID=$(cat "${SCRIPT_DIR}/ollama_quadro.pid")
        if ps -p $QUADRO_PID > /dev/null 2>&1; then
            echo "✓ Quadro P4000 Server: Running (PID: $QUADRO_PID)"
            curl -s http://localhost:11435/api/tags > /dev/null && echo "  → API: Responsive" || echo "  → API: Not responding"
        else
            echo "✗ Quadro P4000 Server: Not running"
        fi
    else
        echo "✗ Quadro P4000 Server: Not running"
    fi
    
    echo
    echo "GPU Usage:"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | while read gpu; do
        echo "  GPU $gpu"
    done
}

load_models() {
    echo "Loading optimized models on each GPU..."
    
    # Load fast model on GTX 1060
    echo "Loading phi-4-mini on GTX 1060..."
    curl -s -X POST http://localhost:11434/api/pull -d '{"name": "ingu627/phi-4-mini-instruct-q4:latest"}' > /dev/null
    
    # Load quality model on Quadro P4000
    echo "Loading qwen3:8b on Quadro P4000..."
    curl -s -X POST http://localhost:11435/api/pull -d '{"name": "qwen3:8b"}' > /dev/null
    
    echo "Models loaded and ready for processing"
}

case "${1:-}" in
    start)
        start_servers
        ;;
    stop)
        stop_servers
        ;;
    status)
        status
        ;;
    restart)
        stop_servers
        sleep 2
        start_servers
        ;;
    load-models)
        load_models
        ;;
    *)
        echo "T3600 GPU Server Manager"
        echo "Usage: $0 {start|stop|status|restart|load-models}"
        echo
        echo "Commands:"
        echo "  start       - Start dual GPU Ollama servers"
        echo "  stop        - Stop all Ollama servers"
        echo "  status      - Check server and GPU status"
        echo "  restart     - Restart both servers"
        echo "  load-models - Pre-load optimized models"
        exit 1
        ;;
esac
EOF
    
    chmod +x "${SCRIPT_DIR}/manage_gpu_servers.sh"
    success "GPU server manager created"
}

# Create optimized document processor
create_document_processor() {
    log "Creating optimized document processor for your models..."
    
    cat > "${SCRIPT_DIR}/process_documents.py" << 'EOF'
#!/usr/bin/env python3
"""
T3600 Document Processor
Optimized for existing Ollama setup with your specific models
"""

import asyncio
import aiohttp
import aiofiles
import json
import time
import argparse
import toml
from pathlib import Path
from typing import List, Dict, Any, Optional
import magic
from tqdm.asyncio import tqdm as atqdm

class T3600DocumentProcessor:
    def __init__(self, config_path: str = "t3600_models.toml"):
        self.config = toml.load(config_path)
        self.session = None
        
        # GPU server configurations
        self.servers = {
            'gtx1060': {'url': 'http://localhost:11434', 'gpu': 0},
            'quadro': {'url': 'http://localhost:11435', 'gpu': 1}
        }
    
    async def __aenter__(self):
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=600))
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        if self.session:
            await self.session.close()
    
    def detect_document_type(self, file_path: Path) -> str:
        """Detect document type for optimal model selection"""
        try:
            mime_type = magic.from_file(str(file_path), mime=True)
            suffix = file_path.suffix.lower()
            
            if suffix in ['.py', '.js', '.cpp', '.java', '.go', '.rs'] or 'code' in str(file_path).lower():
                return 'code_files'
            elif suffix in ['.pdf', '.tex'] or any(word in str(file_path).lower() for word in ['technical', 'spec', 'manual']):
                return 'technical_docs'
            elif file_path.stat().st_size > 50000:  # Large files > 50KB
                return 'large_documents'
            else:
                return 'general_text'
        except:
            return 'general_text'
    
    def get_optimal_config(self, doc_type: str, preference: str = 'balanced') -> Dict[str, Any]:
        """Get optimal processing configuration for document type"""
        type_configs = self.config['document_types'].get(doc_type, ['balanced'])
        
        if preference in type_configs:
            config_name = preference
        else:
            config_name = type_configs[0]
        
        return self.config['processing_configs'][config_name]
    
    async def extract_text(self, file_path: Path) -> str:
        """Extract text from various file formats"""
        suffix = file_path.suffix.lower()
        
        if suffix in ['.txt', '.md', '.py', '.js', '.cpp', '.java', '.html', '.css']:
            async with aiofiles.open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                return await f.read()
        
        elif suffix == '.pdf':
            return self._extract_pdf_text(file_path)
        
        elif suffix in ['.docx', '.doc']:
            return self._extract_docx_text(file_path)
        
        else:
            # Fallback to reading as text
            try:
                async with aiofiles.open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    return await f.read()
            except:
                return ""
    
    def _extract_pdf_text(self, file_path: Path) -> str:
        """Extract text from PDF"""
        try:
            import PyPDF2
            text = ""
            with open(file_path, 'rb') as file:
                pdf_reader = PyPDF2.PdfReader(file)
                for page in pdf_reader.pages:
                    text += page.extract_text()
            return text
        except Exception as e:
            print(f"Error extracting PDF {file_path}: {e}")
            return ""
    
    def _extract_docx_text(self, file_path: Path) -> str:
        """Extract text from DOCX"""
        try:
            from docx import Document
            doc = Document(file_path)
            return "\n".join([paragraph.text for paragraph in doc.paragraphs])
        except Exception as e:
            print(f"Error extracting DOCX {file_path}: {e}")
            return ""
    
    async def process_document(self, file_path: Path, prompt: str, config: Dict[str, Any]) -> Dict[str, Any]:
        """Process single document with specified configuration"""
        
        start_time = time.time()
        
        try:
            # Extract text
            text = await self.extract_text(file_path)
            if not text.strip():
                return {'error': 'No text extracted', 'processing_time': time.time() - start_time}
            
            # Truncate if too long
            max_length = config.get('context_length', 8192)
            if len(text) > max_length:
                text = text[:max_length]
            
            # Determine server URL
            gpu_id = config['gpu']
            server_url = self.servers['gtx1060']['url'] if gpu_id == 0 else self.servers['quadro']['url']
            
            # Prepare request
            payload = {
                'model': config['model'],
                'prompt': f"{prompt}\n\nDocument content:\n{text}",
                'stream': False,
                'options': {
                    'num_ctx': config.get('context_length', 8192),
                    'temperature': 0.7
                }
            }
            
            # Make request
            async with self.session.post(f"{server_url}/api/generate", json=payload) as response:
                if response.status == 200:
                    result = await response.json()
                    return {
                        'file': str(file_path),
                        'model': config['model'],
                        'gpu': f"GPU {gpu_id}",
                        'response': result['response'],
                        'processing_time': time.time() - start_time,
                        'success': True
                    }
                else:
                    error_text = await response.text()
                    return {
                        'error': f"HTTP {response.status}: {error_text}",
                        'processing_time': time.time() - start_time,
                        'success': False
                    }
        
        except Exception as e:
            return {
                'error': str(e),
                'processing_time': time.time() - start_time,
                'success': False
            }
    
    async def process_directory(self, source_dir: Path, target_dir: Path, prompt: str, 
                              processing_mode: str = 'balanced', max_concurrent: int = 4):
        """Process all documents in directory"""
        
        source_dir = Path(source_dir)
        target_dir = Path(target_dir)
        target_dir.mkdir(parents=True, exist_ok=True)
        
        # Find all processable files
        extensions = {'.txt', '.md', '.pdf', '.docx', '.doc', '.py', '.js', '.cpp', '.java', '.html', '.json'}
        files = []
        for ext in extensions:
            files.extend(source_dir.rglob(f'*{ext}'))
        
        if not files:
            print(f"No processable files found in {source_dir}")
            return
        
        print(f"Found {len(files)} files to process")
        
        # Process files with controlled concurrency
        semaphore = asyncio.Semaphore(max_concurrent)
        results = []
        
        async def process_with_semaphore(file_path):
            async with semaphore:
                doc_type = self.detect_document_type(file_path)
                config = self.get_optimal_config(doc_type, processing_mode)
                return await self.process_document(file_path, prompt, config)
        
        # Process with progress bar
        tasks = [process_with_semaphore(file_path) for file_path in files]
        results = await atqdm.gather(*tasks, desc="Processing documents")
        
        # Save individual results
        successful = 0
        failed = 0
        
        for result in results:
            if result.get('success', False):
                file_path = Path(result['file'])
                output_file = target_dir / f"{file_path.stem}_processed.json"
                
                async with aiofiles.open(output_file, 'w') as f:
                    await f.write(json.dumps(result, indent=2))
                successful += 1
            else:
                failed += 1
        
        # Create summary
        summary = {
            'total_files': len(files),
            'successful': successful,
            'failed': failed,
            'processing_mode': processing_mode,
            'avg_processing_time': sum(r.get('processing_time', 0) for r in results) / len(results),
            'model_usage': {}
        }
        
        # Count model usage
        for result in results:
            if 'model' in result:
                model = result['model']
                summary['model_usage'][model] = summary['model_usage'].get(model, 0) + 1
        
        # Save summary
        summary_file = target_dir / 'processing_summary.json'
        async with aiofiles.open(summary_file, 'w') as f:
            await f.write(json.dumps(summary, indent=2))
        
        print(f"\nProcessing complete!")
        print(f"Successful: {successful}, Failed: {failed}")
        print(f"Average processing time: {summary['avg_processing_time']:.2f}s")
        print(f"Results saved to: {target_dir}")

async def main():
    parser = argparse.ArgumentParser(description="T3600 Optimized Document Processor")
    parser.add_argument('source_dir', help="Source directory containing documents")
    parser.add_argument('target_dir', help="Target directory for processed outputs")
    parser.add_argument('--prompt', required=True, help="Processing prompt")
    parser.add_argument('--mode', choices=['fast', 'balanced', 'quality', 'coding', 'reasoning'], 
                       default='balanced', help="Processing mode")
    parser.add_argument('--concurrent', type=int, default=4, help="Max concurrent requests")
    parser.add_argument('--config', default='t3600_models.toml', help="Configuration file")
    
    args = parser.parse_args()
    
    async with T3600DocumentProcessor(args.config) as processor:
        await processor.process_directory(
            args.source_dir, 
            args.target_dir, 
            args.prompt,
            args.mode,
            args.concurrent
        )

if __name__ == "__main__":
    asyncio.run(main())
EOF
    
    chmod +x "${SCRIPT_DIR}/process_documents.py"
    success "Document processor created"
}

# Create simple batch processing wrapper
create_batch_wrapper() {
    log "Creating batch processing wrapper..."
    
    cat > "${SCRIPT_DIR}/batch_process.sh" << 'EOF'
#!/bin/bash

# Simple batch processing wrapper for T3600

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "T3600 Batch Document Processor"
    echo
    echo "Usage: $0 <source_dir> <target_dir> <prompt> [mode]"
    echo
    echo "Modes:"
    echo "  fast      - Quick processing with phi-4-mini (GTX 1060)"
    echo "  balanced  - Balanced processing with hermes3:8b (GTX 1060)" 
    echo "  quality   - High quality with qwen3:8b (Quadro P4000)"
    echo "  coding    - Code analysis with qwen3-coder:30b (Quadro P4000)"
    echo "  reasoning - Advanced reasoning with phi4-reasoning:14b (Quadro P4000)"
    echo
    echo "Examples:"
    echo "  $0 ./documents ./results \"Summarize this document\" quality"
    echo "  $0 ./code_files ./analysis \"Review this code for issues\" coding"
    echo "  $0 ./papers ./summaries \"Extract key findings\" reasoning"
}

if [ $# -lt 3 ]; then
    show_usage
    exit 1
fi

SOURCE_DIR="$1"
TARGET_DIR="$2" 
PROMPT="$3"
MODE="${4:-balanced}"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

echo "=== T3600 Batch Processing ==="
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"
echo "Mode: $MODE"
echo "Prompt: $PROMPT"
echo

# Check if servers are running
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "Starting GPU servers..."
    "${SCRIPT_DIR}/manage_gpu_servers.sh" start
    sleep 5
fi

# Run processing
python3 "${SCRIPT_DIR}/process_documents.py" \
    "$SOURCE_DIR" \
    "$TARGET_DIR" \
    --prompt "$PROMPT" \
    --mode "$MODE" \
    --concurrent 4

echo "Batch processing complete!"
EOF
    
    chmod +x "${SCRIPT_DIR}/batch_process.sh"
    success "Batch processing wrapper created"
}

# Create performance monitor
create_monitor() {
    log "Creating T3600 performance monitor..."
    
    cat > "${SCRIPT_DIR}/monitor.sh" << 'EOF'
#!/bin/bash

# T3600 Performance Monitor

echo "=== T3600 Performance Monitor ==="
echo "Press Ctrl+C to exit"
echo

while true; do
    clear
    echo "=== T3600 Status - $(date) ==="
    echo
    
    # System info
    echo "System:"
    echo "  CPU: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)"
    echo "  RAM: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
    echo "  Load: $(uptime | awk '{print $10 $11 $12}')"
    echo
    
    # GPU status
    echo "GPU Status:"
    nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | while IFS=',' read gpu name util mem_used mem_total temp; do
        printf "  GPU%s %-20s %2s%% %4sMB/%4sMB %2s°C\n" "$gpu" "$name" "$util" "$mem_used" "$mem_total" "$temp"
    done
    echo
    
    # Ollama processes
    echo "Ollama Processes:"
    ps aux | grep -E "ollama serve" | grep -v grep | while read line; do
        pid=$(echo $line | awk '{print $2}')
        cpu=$(echo $line | awk '{print $3}')
        mem=$(echo $line | awk '{print $4}')
        echo "  PID: $pid, CPU: $cpu%, MEM: $mem%"
    done
    echo
    
    # Network connections
    echo "API Status:"
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "  ✓ GTX 1060 (Port 11434): Online"
    else
        echo "  ✗ GTX 1060 (Port 11434): Offline"
    fi
    
    if curl -s http://localhost:11435/api/tags > /dev/null 2>&1; then
        echo "  ✓ Quadro P4000 (Port 11435): Online"
    else
        echo "  ✗ Quadro P4000 (Port 11435): Offline"
    fi
    echo
    
    sleep 5
done
EOF
    
    chmod +x "${SCRIPT_DIR}/monitor.sh"
    success "Performance monitor created"
}

# Create quick test script
create_test_script() {
    log "Creating quick test script..."
    
    cat > "${SCRIPT_DIR}/test_setup.sh" << 'EOF'
#!/bin/bash

# Quick test for T3600 setup

echo "=== T3600 Setup Test ==="

# Create test documents
mkdir -p test_docs
cat > test_docs/sample1.txt << 'TESTEOF'
This is a sample document for testing the T3600 document processing setup.
The Dell Precision T3600 workstation features dual NVIDIA GPUs and is excellent
for parallel document processing with language models.
TESTEOF

cat > test_docs/sample_code.py << 'TESTEOF'
#!/usr/bin/env python3
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)

# This is a simple recursive fibonacci implementation
# Could be optimized with memoization
for i in range(10):
    print(f"fib({i}) = {fibonacci(i)}")
TESTEOF

cat > test_docs/technical_doc.md << 'TESTEOF'
# GPU Processing Architecture

## Overview
Modern GPU architectures enable parallel processing of large language model
inference through CUDA cores and tensor units.

## Key Benefits
- Parallel execution
- High memory bandwidth
- Optimized for matrix operations

## Implementation
Configure CUDA_VISIBLE_DEVICES to assign specific GPUs to different model instances.
TESTEOF

echo "✓ Test documents created"

# Test GPU servers
echo "Testing GPU server startup..."
./manage_gpu_servers.sh start
sleep 5

if ./manage_gpu_servers.sh status | grep -q "✓.*Running"; then
    echo "✓ GPU servers started successfully"
    
    # Test document processing
    echo "Testing document processing..."
    python3 process_documents.py test_docs test_results \
        --prompt "Provide a brief summary of this content" \
        --mode fast \
        --concurrent 2
    
    if [ -d "test_results" ] && [ "$(ls -1 test_results/*.json 2>/dev/null | wc -l)" -gt 0 ]; then
        echo "✓ Document processing test passed"
        echo "Sample results:"
        ls -la test_results/
    else
        echo "✗ Document processing test failed"
    fi
    
    # Test batch wrapper
    echo "Testing batch wrapper..."
    ./batch_process.sh test_docs test_batch "Extract key points" balanced
    
    if [ -d "test_batch" ]; then
        echo "✓ Batch processing test passed"
    else
        echo "✗ Batch processing test failed"
    fi
    
else
    echo "✗ GPU servers failed to start properly"
fi

echo
echo "=== Test Complete ==="
echo "Clean up test files? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    rm -rf test_docs test_results test_batch
    echo "✓ Test files cleaned up"
fi
EOF
    
    chmod +x "${SCRIPT_DIR}/test_setup.sh"
    success "Test script created"
}

# Create utility scripts
create_utilities() {
    log "Creating utility scripts..."
    
    # Result merger
    cat > "${SCRIPT_DIR}/merge_results.py" << 'EOF'
#!/usr/bin/env python3
"""Merge processing results into consolidated formats"""

import json
import argparse
import pandas as pd
from pathlib import Path

def merge_to_json(results_dir, output_file):
    """Merge all JSON results into single file"""
    results_dir = Path(results_dir)
    all_results = []
    
    for json_file in results_dir.glob('*_processed.json'):
        try:
            with open(json_file) as f:
                data = json.load(f)
                all_results.append(data)
        except Exception as e:
            print(f"Error reading {json_file}: {e}")
    
    with open(output_file, 'w') as f:
        json.dump(all_results, f, indent=2)
    
    print(f"Merged {len(all_results)} results to {output_file}")

def merge_to_csv(results_dir, output_file):
    """Merge results to CSV format"""
    results_dir = Path(results_dir)
    rows = []
    
    for json_file in results_dir.glob('*_processed.json'):
        try:
            with open(json_file) as f:
                data = json.load(f)
                if data.get('success'):
                    rows.append({
                        'file': Path(data['file']).name,
                        'model': data.get('model', ''),
                        'gpu': data.get('gpu', ''),
                        'processing_time': data.get('processing_time', 0),
                        'response_length': len(data.get('response', '')),
                        'response': data.get('response', '')[:500] + '...' if len(data.get('response', '')) > 500 else data.get('response', '')
                    })
        except Exception as e:
            print(f"Error reading {json_file}: {e}")
    
    if rows:
        df = pd.DataFrame(rows)
        df.to_csv(output_file, index=False)
        print(f"Merged {len(rows)} rows to {output_file}")
    else:
        print("No valid results found to merge")

def create_summary(results_dir):
    """Create processing summary"""
    results_dir = Path(results_dir)
    
    # Load processing summary if exists
    summary_file = results_dir / 'processing_summary.json'
    if summary_file.exists():
        with open(summary_file) as f:
            summary = json.load(f)
        
        print(f"\n=== Processing Summary ===")
        print(f"Total files: {summary['total_files']}")
        print(f"Successful: {summary['successful']}")
        print(f"Failed: {summary['failed']}")
        print(f"Success rate: {(summary['successful']/summary['total_files']*100):.1f}%")
        print(f"Avg processing time: {summary['avg_processing_time']:.2f}s")
        print(f"Processing mode: {summary['processing_mode']}")
        
        if summary.get('model_usage'):
            print(f"\nModel usage:")
            for model, count in summary['model_usage'].items():
                print(f"  {model}: {count} files")

def main():
    parser = argparse.ArgumentParser(description="Merge processing results")
    parser.add_argument('results_dir', help="Directory containing processed results")
    parser.add_argument('--format', choices=['json', 'csv', 'summary'], default='json')
    parser.add_argument('--output', help="Output file (default: merged_results.json/csv)")
    
    args = parser.parse_args()
    
    if args.format == 'summary':
        create_summary(args.results_dir)
    else:
        if not args.output:
            args.output = f"merged_results.{args.format}"
        
        if args.format == 'json':
            merge_to_json(args.results_dir, args.output)
        else:
            merge_to_csv(args.results_dir, args.output)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "${SCRIPT_DIR}/merge_results.py"
    
    # Model optimizer
    cat > "${SCRIPT_DIR}/optimize_models.sh" << 'EOF'
#!/bin/bash

# Model optimization for T3600 setup

echo "=== T3600 Model Optimization ==="

check_model_size() {
    local model="$1"
    local gpu_mem="$2"
    
    # Get model info from Ollama
    model_info=$(ollama show "$model" 2>/dev/null | grep -E "Parameters|Size")
    if [ $? -eq 0 ]; then
        echo "✓ $model - Available"
        echo "  $model_info" | sed 's/^/  /'
    else
        echo "✗ $model - Not available"
    fi
}

echo "Checking your current models for T3600 optimization..."
echo

echo "GTX 1060 6GB - Recommended models:"
check_model_size "ingu627/phi-4-mini-instruct-q4:latest" "6GB"
check_model_size "ingu627/EXAONE-Deep-7.8B:latest" "6GB" 
check_model_size "hermes3:8b" "6GB"

echo
echo "Quadro P4000 8GB - Recommended models:"
check_model_size "qwen3:8b" "8GB"
check_model_size "mistral-nemo:12b" "8GB"
check_model_size "mannix/smaug-llama3-8b:q8_0" "8GB"

echo
echo "Large models (may require CPU offloading):"
check_model_size "phi4-reasoning:14b" ">8GB"
check_model_size "qwen3-coder:30b" ">8GB"
check_model_size "mistral-nemo:12b-instruct-2407-q8_0" ">8GB"

echo
echo "Memory usage recommendations:"
echo "  GTX 1060: Use models under 5.5GB for best performance"  
echo "  Quadro P4000: Use models under 7.5GB for best performance"
echo "  Large models: Will use CPU RAM for overflow (slower but works)"

# Performance test
echo
echo "Would you like to run a performance test? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "Running performance tests..."
    
    # Test small model
    echo "Testing phi-4-mini (GTX 1060)..."
    time curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model": "ingu627/phi-4-mini-instruct-q4:latest", "prompt": "Explain quantum computing in one sentence.", "stream": false}' \
        | jq -r '.response'
    
    echo
    
    # Test medium model  
    echo "Testing qwen3:8b (Quadro P4000)..."
    time curl -s -X POST http://localhost:11435/api/generate \
        -H "Content-Type: application/json" \
        -d '{"model": "qwen3:8b", "prompt": "Explain quantum computing in one sentence.", "stream": false}' \
        | jq -r '.response'
fi
EOF
    
    chmod +x "${SCRIPT_DIR}/optimize_models.sh"
    
    success "Utility scripts created"
}

# Main menu
show_menu() {
    echo
    echo "=== T3600 Document Processor (Existing Setup) ==="
    echo "Your current models: qwen3:8b, mistral-nemo:12b, phi4-reasoning:14b, etc."
    echo
    echo "1. Setup Python dependencies"
    echo "2. Create configuration files" 
    echo "3. Create GPU server manager"
    echo "4. Create document processor"
    echo "5. Create batch wrapper"
    echo "6. Create monitoring tools"
    echo "7. Create utilities"
    echo "8. Run complete setup (1-7)"
    echo "9. Start GPU servers"
    echo "10. Test setup"
    echo "11. Process documents (interactive)"
    echo "12. Monitor performance"
    echo "13. Exit"
    echo
}

# Interactive document processing
process_documents_interactive() {
    echo
    echo "=== Interactive Document Processing ==="
    read -p "Source directory: " source_dir
    read -p "Target directory: " target_dir
    
    echo "Processing modes:"
    echo "  fast      - phi-4-mini (GTX 1060) - Quick processing"
    echo "  balanced  - hermes3:8b (GTX 1060) - Good balance" 
    echo "  quality   - qwen3:8b (P4000) - High quality responses"
    echo "  coding    - qwen3-coder:30b (P4000) - Code analysis"
    echo "  reasoning - phi4-reasoning:14b (P4000) - Complex reasoning"
    read -p "Processing mode [balanced]: " mode
    mode=${mode:-balanced}
    
    read -p "Processing prompt: " prompt
    
    if [ ! -d "$source_dir" ]; then
        error "Source directory does not exist: $source_dir"
        return 1
    fi
    
    # Check if servers are running
    if ! curl -s http://localhost:11434/api/tags > /dev/null; then
        warning "GPU servers not running. Starting them..."
        "${SCRIPT_DIR}/manage_gpu_servers.sh" start
        sleep 5
    fi
    
    # Run processing
    "${SCRIPT_DIR}/batch_process.sh" "$source_dir" "$target_dir" "$prompt" "$mode"
}

# Main execution
main() {
    log "T3600 Document Processor (Existing Setup) starting..."
    
    while true; do
        show_menu
        read -p "Choose an option: " choice
        
        case $choice in
            1) setup_python_deps ;;
            2) create_model_config ;;
            3) create_gpu_server_manager ;;
            4) create_document_processor ;;
            5) create_batch_wrapper ;;
            6) 
                create_monitor
                create_test_script
                ;;
            7) create_utilities ;;
            8)
                setup_python_deps
                create_model_config
                create_gpu_server_manager
                create_document_processor
                create_batch_wrapper
                create_monitor
                create_test_script
                create_utilities
                success "Complete setup finished!"
                ;;
            9)
                "${SCRIPT_DIR}/manage_gpu_servers.sh" start
                ;;
            10)
                if [ -x "${SCRIPT_DIR}/test_setup.sh" ]; then
                    "${SCRIPT_DIR}/test_setup.sh"
                else
                    warning "Run setup first (option 8)"
                fi
                ;;
            11) process_documents_interactive ;;
            12)
                if [ -x "${SCRIPT_DIR}/monitor.sh" ]; then
                    "${SCRIPT_DIR}/monitor.sh"
                else
                    warning "Run setup first (option 8)"
                fi
                ;;
            13)
                success "Goodbye!"
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

# Execute if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_existing_setup
    main "$@"
fi
