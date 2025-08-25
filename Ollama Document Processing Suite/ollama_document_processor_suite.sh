#!/bin/bash

# Ollama Document Processing Suite
# A comprehensive toolkit for batch processing documents with Ollama
# Optimized for Ubuntu 24.04 with GPU acceleration

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/ollama-processor.conf"
LOG_FILE="${SCRIPT_DIR}/processing.log"
PYTHON_ENV="${SCRIPT_DIR}/venv"
TEMP_DIR="${SCRIPT_DIR}/temp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Check system requirements
check_system() {
    info "Checking system requirements..."
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu 24.04" /etc/os-release; then
        warning "This script is optimized for Ubuntu 24.04"
    fi
    
    # Check if running on T3600 with GPUs
    if command -v nvidia-smi &> /dev/null; then
        GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader)
        info "Detected GPUs: $GPU_INFO"
    else
        warning "NVIDIA drivers/CUDA not detected"
    fi
    
    # Check Ollama installation
    if ! command -v ollama &> /dev/null; then
        error "Ollama not found. Please install Ollama first."
        echo "Visit: https://ollama.ai"
        exit 1
    fi
    
    success "System check completed"
}

# Setup Python environment and dependencies
setup_environment() {
    info "Setting up Python environment..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "$PYTHON_ENV" ]; then
        python3 -m venv "$PYTHON_ENV"
    fi
    
    # Activate virtual environment
    source "$PYTHON_ENV/bin/activate"
    
    # Install/upgrade required packages
    pip install --upgrade pip
    pip install -r "${SCRIPT_DIR}/requirements.txt" 2>/dev/null || {
        # Create requirements.txt if it doesn't exist
        cat > "${SCRIPT_DIR}/requirements.txt" << EOF
ollama>=0.3.0
python-docx>=1.1.0
pypdf2>=3.0.0
langchain>=0.3.0
langchain-community>=0.3.0
python-magic>=0.4.27
toml>=0.10.2
click>=8.1.0
tqdm>=4.66.0
requests>=2.31.0
beautifulsoup4>=4.12.0
pillow>=10.0.0
pandas>=2.1.0
jinja2>=3.1.0
EOF
        pip install -r "${SCRIPT_DIR}/requirements.txt"
    }
    
    success "Python environment ready"
}

# Create configuration file
create_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        info "Creating configuration file..."
        
        cat > "$CONFIG_FILE" << EOF
# Ollama Document Processor Configuration

[ollama]
model = "llama3.2:3b"
base_url = "http://localhost:11434"
timeout = 300
max_retries = 3

[processing]
batch_size = 10
max_workers = 4
chunk_size = 4000
overlap_size = 200

[output]
format = "markdown"  # Options: markdown, json, text, structured
include_metadata = true
preserve_structure = true

[models]
# Recommended models for different tasks
text_processing = "llama3.2:3b"
code_analysis = "codellama:7b"
structured_extraction = "qwen2.5:7b"
vision_ocr = "llama3.2-vision:11b"
embedding = "nomic-embed-text"

[gpu]
# GPU configuration for multi-GPU setups
use_multiple_gpus = true
gpus_per_model = 1
start_port = 11432
EOF
        success "Configuration file created at $CONFIG_FILE"
    fi
}

# Install additional tools
install_tools() {
    info "Installing additional document processing tools..."
    
    # Install system dependencies
    sudo apt-get update
    sudo apt-get install -y \
        python3-dev \
        python3-pip \
        python3-venv \
        libmagic1 \
        poppler-utils \
        tesseract-ocr \
        imagemagick \
        pandoc \
        git \
        curl \
        jq
    
    # Clone useful repositories
    REPOS_DIR="${SCRIPT_DIR}/repos"
    mkdir -p "$REPOS_DIR"
    
    # Robert McDermott's batch processing cluster
    if [ ! -d "$REPOS_DIR/ollama-batch-cluster" ]; then
        git clone https://github.com/robert-mcdermott/ollama-batch-cluster.git "$REPOS_DIR/ollama-batch-cluster"
    fi
    
    # Simple ollama-batch tool
    if [ ! -d "$REPOS_DIR/ollama-batch" ]; then
        git clone https://github.com/emi420/ollama-batch.git "$REPOS_DIR/ollama-batch"
    fi
    
    # Ollama OCR for image/PDF processing
    if [ ! -d "$REPOS_DIR/ollama-ocr" ]; then
        git clone https://github.com/imanoop7/Ollama-OCR.git "$REPOS_DIR/ollama-ocr"
    fi
    
    success "Additional tools installed"
}

# Create the main document processor
create_processor() {
    info "Creating document processor..."
    
    cat > "${SCRIPT_DIR}/document_processor.py" << 'EOF'
#!/usr/bin/env python3
"""
Advanced Ollama Document Processor
Processes documents from source directory and saves results to target directory
"""

import os
import sys
import json
import time
import asyncio
import logging
import argparse
import toml
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from typing import List, Dict, Any, Optional
import magic
import ollama
from tqdm import tqdm

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DocumentProcessor:
    def __init__(self, config_path: str):
        self.config = toml.load(config_path)
        self.client = ollama.Client(host=self.config['ollama']['base_url'])
        self.supported_extensions = {'.txt', '.md', '.pdf', '.docx', '.doc', '.rtf', '.html', '.json', '.xml'}
        
    def detect_file_type(self, file_path: Path) -> str:
        """Detect file type using python-magic"""
        try:
            mime_type = magic.from_file(str(file_path), mime=True)
            return mime_type
        except Exception as e:
            logger.warning(f"Could not detect file type for {file_path}: {e}")
            return file_path.suffix.lower()
    
    def extract_text(self, file_path: Path) -> str:
        """Extract text from various file formats"""
        file_type = self.detect_file_type(file_path)
        
        if file_type.startswith('text/') or file_path.suffix in ['.txt', '.md']:
            return file_path.read_text(encoding='utf-8', errors='ignore')
        
        elif file_type == 'application/pdf' or file_path.suffix == '.pdf':
            return self._extract_pdf_text(file_path)
        
        elif 'word' in file_type or file_path.suffix in ['.docx', '.doc']:
            return self._extract_docx_text(file_path)
        
        elif file_type.startswith('image/'):
            return self._extract_image_text(file_path)
        
        else:
            logger.warning(f"Unsupported file type: {file_type} for {file_path}")
            return ""
    
    def _extract_pdf_text(self, file_path: Path) -> str:
        """Extract text from PDF using PyPDF2"""
        try:
            import PyPDF2
            text = ""
            with open(file_path, 'rb') as file:
                pdf_reader = PyPDF2.PdfReader(file)
                for page in pdf_reader.pages:
                    text += page.extract_text()
            return text
        except Exception as e:
            logger.error(f"Error extracting PDF text from {file_path}: {e}")
            return ""
    
    def _extract_docx_text(self, file_path: Path) -> str:
        """Extract text from DOCX using python-docx"""
        try:
            from docx import Document
            doc = Document(file_path)
            text = "\n".join([paragraph.text for paragraph in doc.paragraphs])
            return text
        except Exception as e:
            logger.error(f"Error extracting DOCX text from {file_path}: {e}")
            return ""
    
    def _extract_image_text(self, file_path: Path) -> str:
        """Extract text from images using OCR via Ollama vision model"""
        try:
            vision_model = self.config['models'].get('vision_ocr', 'llama3.2-vision:11b')
            
            response = self.client.generate(
                model=vision_model,
                prompt="Extract all text from this image. Return only the text content, no descriptions.",
                images=[str(file_path)]
            )
            return response['response']
        except Exception as e:
            logger.error(f"Error extracting image text from {file_path}: {e}")
            return ""
    
    def chunk_text(self, text: str, chunk_size: int = 4000, overlap: int = 200) -> List[str]:
        """Split text into overlapping chunks"""
        if len(text) <= chunk_size:
            return [text]
        
        chunks = []
        start = 0
        while start < len(text):
            end = start + chunk_size
            if end > len(text):
                end = len(text)
            
            chunks.append(text[start:end])
            start = end - overlap
            if start >= len(text):
                break
                
        return chunks
    
    def process_document(self, file_path: Path, prompt: str, output_dir: Path) -> Dict[str, Any]:
        """Process a single document"""
        logger.info(f"Processing: {file_path}")
        
        try:
            # Extract text
            text = self.extract_text(file_path)
            if not text.strip():
                logger.warning(f"No text extracted from {file_path}")
                return {"error": "No text extracted"}
            
            # Chunk text if necessary
            chunks = self.chunk_text(
                text,
                self.config['processing']['chunk_size'],
                self.config['processing']['overlap_size']
            )
            
            results = []
            model = self.config['ollama']['model']
            
            # Process each chunk
            for i, chunk in enumerate(chunks):
                full_prompt = f"{prompt}\n\nDocument content:\n{chunk}"
                
                response = self.client.generate(
                    model=model,
                    prompt=full_prompt,
                    options={
                        'temperature': 0.7,
                        'top_p': 0.9,
                    }
                )
                
                results.append({
                    'chunk_id': i,
                    'prompt': prompt,
                    'response': response['response'],
                    'chunk_text': chunk if self.config['output']['include_metadata'] else None
                })
            
            # Save results
            output_file = output_dir / f"{file_path.stem}.json"
            result = {
                'source_file': str(file_path),
                'processing_time': time.time(),
                'model_used': model,
                'chunks_processed': len(chunks),
                'results': results
            }
            
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(result, f, indent=2, ensure_ascii=False)
            
            logger.info(f"Completed: {file_path} -> {output_file}")
            return result
            
        except Exception as e:
            logger.error(f"Error processing {file_path}: {e}")
            return {"error": str(e)}
    
    def process_directory(self, source_dir: Path, target_dir: Path, prompt: str):
        """Process all documents in a directory"""
        source_dir = Path(source_dir)
        target_dir = Path(target_dir)
        target_dir.mkdir(parents=True, exist_ok=True)
        
        # Find all processable files
        files = []
        for ext in self.supported_extensions:
            files.extend(source_dir.rglob(f"*{ext}"))
        
        logger.info(f"Found {len(files)} files to process")
        
        # Process files with progress bar
        max_workers = self.config['processing']['max_workers']
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self.process_document, file_path, prompt, target_dir)
                for file_path in files
            ]
            
            results = []
            for future in tqdm(futures, desc="Processing documents"):
                result = future.result()
                results.append(result)
        
        # Save summary
        summary = {
            'total_files': len(files),
            'successful': len([r for r in results if 'error' not in r]),
            'failed': len([r for r in results if 'error' in r]),
            'processing_time': time.time(),
            'configuration': self.config
        }
        
        summary_file = target_dir / 'processing_summary.json'
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        logger.info(f"Processing complete. Summary saved to {summary_file}")

def main():
    parser = argparse.ArgumentParser(description="Ollama Document Processor")
    parser.add_argument('source_dir', help="Source directory containing documents")
    parser.add_argument('target_dir', help="Target directory for processed outputs")
    parser.add_argument('--prompt', required=True, help="Prompt to apply to each document")
    parser.add_argument('--config', default='ollama-processor.conf', help="Configuration file path")
    parser.add_argument('--model', help="Override model from config")
    
    args = parser.parse_args()
    
    # Initialize processor
    processor = DocumentProcessor(args.config)
    
    # Override model if specified
    if args.model:
        processor.config['ollama']['model'] = args.model
    
    # Process documents
    processor.process_directory(args.source_dir, args.target_dir, args.prompt)

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "${SCRIPT_DIR}/document_processor.py"
    success "Document processor created"
}

# Create GPU server management script
create_gpu_manager() {
    info "Creating GPU server manager..."
    
    cat > "${SCRIPT_DIR}/gpu_manager.sh" << 'EOF'
#!/bin/bash

# GPU Server Manager for Ollama
# Based on Robert McDermott's batch processing approach

GPU_MANAGER_LOG="${SCRIPT_DIR}/gpu_manager.log"

start_ollama_servers() {
    local num_gpus=${1:-1}
    local base_port=11432
    
    echo "Starting $num_gpus Ollama servers..."
    
    for ((i=0; i<num_gpus; i++)); do
        local port=$((base_port + i))
        local gpu_id=$i
        
        echo "Starting Ollama server on GPU $gpu_id, port $port"
        
        # Set GPU and start server
        CUDA_VISIBLE_DEVICES=$gpu_id OLLAMA_HOST="0.0.0.0:$port" ollama serve > "ollama_gpu_${gpu_id}.log" 2>&1 &
        local pid=$!
        echo $pid > "ollama_gpu_${gpu_id}.pid"
        
        sleep 2
    done
    
    echo "All servers started. Use stop_ollama_servers to stop them."
}

stop_ollama_servers() {
    echo "Stopping Ollama servers..."
    
    for pidfile in ollama_gpu_*.pid; do
        if [ -f "$pidfile" ]; then
            local pid=$(cat "$pidfile")
            if kill "$pid" 2>/dev/null; then
                echo "Stopped server with PID $pid"
            fi
            rm -f "$pidfile"
        fi
    done
    
    # Cleanup log files older than 7 days
    find . -name "ollama_gpu_*.log" -mtime +7 -delete
}

check_servers() {
    echo "Checking Ollama servers..."
    
    for pidfile in ollama_gpu_*.pid; do
        if [ -f "$pidfile" ]; then
            local pid=$(cat "$pidfile")
            local gpu_id=$(basename "$pidfile" .pid | sed 's/ollama_gpu_//')
            
            if ps -p "$pid" > /dev/null; then
                echo "GPU $gpu_id (PID $pid): Running"
            else
                echo "GPU $gpu_id (PID $pid): Not running"
                rm -f "$pidfile"
            fi
        fi
    done
}

case "${1:-}" in
    start)
        start_ollama_servers "${2:-1}"
        ;;
    stop)
        stop_ollama_servers
        ;;
    status)
        check_servers
        ;;
    restart)
        stop_ollama_servers
        sleep 3
        start_ollama_servers "${2:-1}"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart} [num_gpus]"
        echo "  start [num_gpus] - Start Ollama servers (default: 1 GPU)"
        echo "  stop             - Stop all Ollama servers"
        echo "  status           - Check server status"
        echo "  restart [num_gpus] - Restart servers"
        exit 1
        ;;
esac
EOF
    
    chmod +x "${SCRIPT_DIR}/gpu_manager.sh"
    success "GPU manager created"
}

# Create usage examples
create_examples() {
    info "Creating usage examples..."
    
    mkdir -p "${SCRIPT_DIR}/examples"
    
    # Example 1: Basic document processing
    cat > "${SCRIPT_DIR}/examples/example1_basic.sh" << EOF
#!/bin/bash
# Basic document processing example

SOURCE_DIR="./test_documents"
TARGET_DIR="./results/basic"
PROMPT="Summarize this document in 3 bullet points."

# Create test documents directory
mkdir -p "\$SOURCE_DIR"

# Process documents
python3 ../document_processor.py "\$SOURCE_DIR" "\$TARGET_DIR" --prompt "\$PROMPT"
EOF
    
    # Example 2: Code analysis
    cat > "${SCRIPT_DIR}/examples/example2_code_analysis.sh" << EOF
#!/bin/bash
# Code analysis example

SOURCE_DIR="./code_files"
TARGET_DIR="./results/code_analysis"
PROMPT="Analyze this code for potential improvements, security issues, and documentation quality."

python3 ../document_processor.py "\$SOURCE_DIR" "\$TARGET_DIR" \\
    --prompt "\$PROMPT" \\
    --model "codellama:7b"
EOF
    
    # Example 3: Structured data extraction
    cat > "${SCRIPT_DIR}/examples/example3_extraction.sh" << EOF
#!/bin/bash
# Structured data extraction example

SOURCE_DIR="./unstructured_docs"
TARGET_DIR="./results/structured"
PROMPT="Extract key information from this document and return it as JSON with fields: title, summary, key_points, entities."

python3 ../document_processor.py "\$SOURCE_DIR" "\$TARGET_DIR" \\
    --prompt "\$PROMPT" \\
    --model "qwen2.5:7b"
EOF
    
    chmod +x "${SCRIPT_DIR}"/examples/*.sh
    success "Examples created in ${SCRIPT_DIR}/examples/"
}

# Create utilities
create_utilities() {
    info "Creating utility scripts..."
    
    # Result merger
    cat > "${SCRIPT_DIR}/merge_results.py" << 'EOF'
#!/usr/bin/env python3
"""Merge processing results into various formats"""

import json
import argparse
from pathlib import Path
import pandas as pd

def merge_to_json(results_dir, output_file):
    """Merge all JSON results into a single file"""
    results_dir = Path(results_dir)
    all_results = []
    
    for json_file in results_dir.glob('*.json'):
        if json_file.name == 'processing_summary.json':
            continue
        
        with open(json_file) as f:
            data = json.load(f)
            all_results.append(data)
    
    with open(output_file, 'w') as f:
        json.dump(all_results, f, indent=2)
    
    print(f"Merged {len(all_results)} results to {output_file}")

def merge_to_csv(results_dir, output_file):
    """Merge results into CSV format"""
    results_dir = Path(results_dir)
    rows = []
    
    for json_file in results_dir.glob('*.json'):
        if json_file.name == 'processing_summary.json':
            continue
        
        with open(json_file) as f:
            data = json.load(f)
            for result in data.get('results', []):
                rows.append({
                    'source_file': data['source_file'],
                    'chunk_id': result['chunk_id'],
                    'response': result['response'],
                    'model_used': data['model_used']
                })
    
    df = pd.DataFrame(rows)
    df.to_csv(output_file, index=False)
    print(f"Merged {len(rows)} rows to {output_file}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('results_dir', help="Directory containing JSON results")
    parser.add_argument('--output', required=True, help="Output file")
    parser.add_argument('--format', choices=['json', 'csv'], default='json')
    
    args = parser.parse_args()
    
    if args.format == 'json':
        merge_to_json(args.results_dir, args.output)
    else:
        merge_to_csv(args.results_dir, args.output)

if __name__ == '__main__':
    main()
EOF
    
    chmod +x "${SCRIPT_DIR}/merge_results.py"
    success "Utilities created"
}

# Main menu
show_menu() {
    echo
    echo "=== Ollama Document Processor Suite ==="
    echo "1. Setup/Install everything"
    echo "2. Start GPU servers"
    echo "3. Stop GPU servers"
    echo "4. Process documents"
    echo "5. Check system status"
    echo "6. View examples"
    echo "7. Run batch processing (advanced)"
    echo "8. Exit"
    echo
}

# Process documents interactively
process_documents_interactive() {
    echo
    read -p "Source directory: " source_dir
    read -p "Target directory: " target_dir
    read -p "Processing prompt: " prompt
    
    if [ ! -d "$source_dir" ]; then
        error "Source directory does not exist: $source_dir"
        return 1
    fi
    
    mkdir -p "$target_dir"
    
    # Activate Python environment
    source "$PYTHON_ENV/bin/activate"
    
    # Run processor
    python3 "${SCRIPT_DIR}/document_processor.py" "$source_dir" "$target_dir" --prompt "$prompt"
}

# Advanced batch processing
run_batch_processing() {
    info "Setting up advanced batch processing..."
    
    # Check if batch cluster repo is available
    BATCH_CLUSTER_DIR="${SCRIPT_DIR}/repos/ollama-batch-cluster"
    
    if [ ! -d "$BATCH_CLUSTER_DIR" ]; then
        error "Batch cluster repository not found. Please run setup first."
        return 1
    fi
    
    echo "Advanced batch processing options:"
    echo "1. Use Robert McDermott's batch cluster"
    echo "2. Use simple ollama-batch tool"
    echo "3. Return to main menu"
    
    read -p "Choice: " choice
    
    case $choice in
        1)
            cd "$BATCH_CLUSTER_DIR"
            info "Batch cluster tools available in: $BATCH_CLUSTER_DIR"
            info "See README.md for detailed usage instructions"
            ;;
        2)
            SIMPLE_BATCH_DIR="${SCRIPT_DIR}/repos/ollama-batch"
            if [ -d "$SIMPLE_BATCH_DIR" ]; then
                cd "$SIMPLE_BATCH_DIR"
                info "Simple batch tools available in: $SIMPLE_BATCH_DIR"
                python3 ollama-batch.py --help
            else
                error "Simple batch repository not found"
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# Main execution
main() {
    # Create necessary directories
    mkdir -p "$TEMP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Initialize log
    log "Ollama Document Processor Suite starting..."
    
    while true; do
        show_menu
        read -p "Choose an option: " choice
        
        case $choice in
            1)
                check_system
                create_config
                setup_environment
                install_tools
                create_processor
                create_gpu_manager
                create_examples
                create_utilities
                success "Setup completed successfully!"
                ;;
            2)
                read -p "Number of GPUs to use (default: 2): " num_gpus
                num_gpus=${num_gpus:-2}
                "${SCRIPT_DIR}/gpu_manager.sh" start "$num_gpus"
                ;;
            3)
                "${SCRIPT_DIR}/gpu_manager.sh" stop
                ;;
            4)
                process_documents_interactive
                ;;
            5)
                check_system
                "${SCRIPT_DIR}/gpu_manager.sh" status
                ;;
            6)
                info "Example scripts available in: ${SCRIPT_DIR}/examples/"
                ls -la "${SCRIPT_DIR}/examples/" 2>/dev/null || echo "Run setup first to create examples"
                ;;
            7)
                run_batch_processing
                ;;
            8)
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

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
