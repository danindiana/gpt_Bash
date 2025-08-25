#!/bin/bash

# T3600 Quick Start - Document Processing with Your Existing Ollama Setup
# This script gets you up and running immediately with your current models

set -euo pipefail

echo "=========================================="
echo "  T3600 Ollama Document Processor"
echo "  Quick Start for Existing Setup"
echo "=========================================="
echo
echo "Your system: Ollama 0.11.4 with excellent models!"
echo "Detected models: qwen3:8b, mistral-nemo:12b, phi4-reasoning:14b, etc."
echo

# Quick setup function
quick_setup() {
    echo "Setting up in 30 seconds..."
    
    # Install minimal Python deps
    pip3 install --user aiohttp aiofiles python-docx pypdf2 python-magic tqdm requests toml pandas pillow > /dev/null 2>&1
    
    # Create simple config
    cat > t3600_quick.toml << 'EOF'
[models]
fast_model = "ingu627/phi-4-mini-instruct-q4:latest"
quality_model = "qwen3:8b" 
coding_model = "qwen3-coder:30b"
reasoning_model = "phi4-reasoning:14b"

[servers]
gtx1060_url = "http://localhost:11434"
quadro_url = "http://localhost:11435"
EOF
    
    # Create enhanced processor with better file discovery and progress
    cat > quick_process.py << 'EOF'
#!/usr/bin/env python3
import asyncio
import aiohttp
import json
import time
import sys
from pathlib import Path
from tqdm.asyncio import tqdm as atqdm

def find_processable_files(directory):
    """Find all processable files with enhanced detection"""
    extensions = ['.txt', '.md', '.py', '.js', '.java', '.cpp', '.html', '.css', '.json', '.csv', '.xml']
    files = []
    directory = Path(directory)
    
    # Find files with known extensions
    for ext in extensions:
        files.extend(directory.rglob(f'*{ext}'))
        files.extend(directory.rglob(f'*{ext.upper()}'))
    
    # Look for text files without extensions
    for file_path in directory.rglob('*'):
        if file_path.is_file() and file_path.suffix == '' and file_path.stat().st_size < 1024*1024:  # < 1MB
            try:
                # Quick check if it's text
                with open(file_path, 'rb') as f:
                    chunk = f.read(512)
                    # Simple heuristic: if mostly printable ASCII, it's probably text
                    if chunk and all(b in range(9, 127) for b in chunk[:100] if b != 0):
                        files.append(file_path)
            except:
                pass
    
    return sorted(set(files))

async def process_file(session, file_path, prompt, model, server):
    """Process single file with enhanced error handling"""
    try:
        # Read file with better encoding handling
        content = ""
        for encoding in ['utf-8', 'latin-1', 'cp1252']:
            try:
                with open(file_path, 'r', encoding=encoding) as f:
                    content = f.read()[:12000]  # Increased limit
                break
            except UnicodeDecodeError:
                continue
        
        if not content.strip():
            return {"file": str(file_path), "error": "No readable content", "success": False}
        
        # Prepare optimized payload
        payload = {
            "model": model,
            "prompt": f"{prompt}\n\nDocument content:\n{content}",
            "stream": False,
            "options": {
                "temperature": 0.7,
                "top_p": 0.9,
                "num_ctx": 8192
            }
        }
        
        async with session.post(f"{server}/api/generate", json=payload) as resp:
            if resp.status == 200:
                result = await resp.json()
                return {
                    "file": str(file_path),
                    "model": model,
                    "server": server,
                    "response": result["response"],
                    "processing_time": result.get("total_duration", 0) / 1e9,  # Convert to seconds
                    "success": True
                }
            else:
                error_text = await resp.text()
                return {"file": str(file_path), "error": f"HTTP {resp.status}: {error_text[:200]}", "success": False}
                
    except Exception as e:
        return {"file": str(file_path), "error": str(e)[:200], "success": False}

async def process_with_progress(session, files, prompt, model, server, batch_size=3):
    """Process files with progress indicator and batching"""
    results = []
    
    async with atqdm(total=len(files), desc=f"Processing with {model.split(':')[0]}") as pbar:
        for i in range(0, len(files), batch_size):
            batch = files[i:i+batch_size]
            
            # Process batch
            tasks = [process_file(session, f, prompt, model, server) for f in batch]
            batch_results = await asyncio.gather(*tasks)
            results.extend(batch_results)
            
            # Update progress
            pbar.update(len(batch))
            
            # Show quick stats
            successful = sum(1 for r in batch_results if r.get("success"))
            pbar.set_postfix({"Success": f"{successful}/{len(batch)}"})
            
            # Brief pause to prevent overwhelming the server
            await asyncio.sleep(0.5)
    
    return results

def select_optimal_model_and_server(file_path, available_models):
    """Select optimal model and server based on file type"""
    file_path = Path(file_path)
    
    # Code files -> coding model on Quadro P4000
    if file_path.suffix.lower() in ['.py', '.js', '.java', '.cpp', '.c', '.go', '.rs', '.php']:
        if "qwen3-coder:30b" in available_models:
            return "qwen3-coder:30b", "http://localhost:11435"
        elif "qwen3:8b" in available_models:
            return "qwen3:8b", "http://localhost:11435"
    
    # Large or technical files -> quality model on Quadro P4000  
    if file_path.stat().st_size > 10000 or any(word in str(file_path).lower() for word in ['doc', 'spec', 'manual', 'technical']):
        if "qwen3:8b" in available_models:
            return "qwen3:8b", "http://localhost:11435"
        elif "phi4-reasoning:14b" in available_models:
            return "phi4-reasoning:14b", "http://localhost:11435"
    
    # Default: fast model on GTX 1060
    if "ingu627/phi-4-mini-instruct-q4:latest" in available_models:
        return "ingu627/phi-4-mini-instruct-q4:latest", "http://localhost:11434"
    elif "hermes3:8b" in available_models:
        return "hermes3:8b", "http://localhost:11434"
    else:
        # Fallback to qwen3:8b on Quadro
        return "qwen3:8b", "http://localhost:11435"

async def main():
    if len(sys.argv) < 4:
        print("Usage: python3 quick_process.py <source_dir> <target_dir> <prompt> [model_choice]")
        print("\nModel choices:")
        print("  1 - qwen3:8b (Quality - Quadro P4000)")
        print("  2 - phi4-reasoning:14b (Reasoning - Quadro P4000)")
        print("  3 - qwen3-coder:30b (Coding - Quadro P4000)")
        print("  4 - hermes3:8b (Balanced - GTX 1060)")
        print("  5 - phi-4-mini (Fast - GTX 1060)")
        print("  auto - Automatic selection based on file type (default)")
        print("\nExample: python3 quick_process.py ./docs ./results 'Summarize this document' auto")
        sys.exit(1)
    
    source_dir = Path(sys.argv[1])
    target_dir = Path(sys.argv[2])
    prompt = sys.argv[3]
    model_choice = sys.argv[4] if len(sys.argv) > 4 else "auto"
    
    target_dir.mkdir(exist_ok=True)
    
    # Find files with enhanced detection
    files = find_processable_files(source_dir)
    
    if not files:
        print("No processable files found!")
        print("Supported: .txt, .md, .py, .js, .java, .cpp, .html, .css, .json, .csv, .xml, and text files without extensions")
        sys.exit(1)
    
    print(f"Found {len(files)} processable files")
    
    # Model selection
    model_map = {
        "1": ("qwen3:8b", "http://localhost:11435"),
        "2": ("phi4-reasoning:14b", "http://localhost:11435"),
        "3": ("qwen3-coder:30b", "http://localhost:11435"),
        "4": ("hermes3:8b", "http://localhost:11434"),
        "5": ("ingu627/phi-4-mini-instruct-q4:latest", "http://localhost:11434")
    }
    
    # Get available models
    try:
        import subprocess
        result = subprocess.run(['ollama', 'list'], capture_output=True, text=True)
        available_models = [line.split()[0] for line in result.stdout.strip().split('\n')[1:] if line.strip()]
    except:
        available_models = ["qwen3:8b"]  # Fallback
    
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(600)) as session:
        if model_choice == "auto":
            # Group files by optimal model
            model_groups = {}
            for file_path in files:
                model, server = select_optimal_model_and_server(file_path, available_models)
                key = (model, server)
                if key not in model_groups:
                    model_groups[key] = []
                model_groups[key].append(file_path)
            
            # Process each group
            all_results = []
            for (model, server), group_files in model_groups.items():
                print(f"\nProcessing {len(group_files)} files with {model}")
                results = await process_with_progress(session, group_files, prompt, model, server)
                all_results.extend(results)
        
        else:
            if model_choice in model_map:
                model, server = model_map[model_choice]
            else:
                model, server = "qwen3:8b", "http://localhost:11435"
            
            print(f"Processing all files with {model}")
            all_results = await process_with_progress(session, files, prompt, model, server)
        
        # Save results with enhanced metadata
        successful = 0
        failed = 0
        total_time = 0
        
        for result in all_results:
            if result.get("success"):
                output_file = target_dir / f"{Path(result['file']).stem}_result.json"
                
                # Add processing metadata
                result["processed_at"] = time.time()
                result["file_size"] = Path(result['file']).stat().st_size
                
                with open(output_file, 'w', encoding='utf-8') as f:
                    json.dump(result, f, indent=2, ensure_ascii=False)
                
                successful += 1
                total_time += result.get("processing_time", 0)
                print(f"✓ {Path(result['file']).name}")
            else:
                failed += 1
                print(f"✗ {Path(result['file']).name}: {result.get('error', 'Unknown error')}")
        
        # Create summary
        summary = {
            "total_files": len(all_results),
            "successful": successful,
            "failed": failed,
            "success_rate": f"{(successful/len(all_results)*100):.1f}%" if all_results else "0%",
            "total_processing_time": f"{total_time:.1f}s",
            "average_time_per_file": f"{(total_time/successful):.1f}s" if successful > 0 else "N/A",
            "processed_at": time.time(),
            "models_used": list(set(r.get("model", "") for r in all_results if r.get("success")))
        }
        
        with open(target_dir / "processing_summary.json", 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"\n=== Processing Complete ===")
        print(f"Successful: {successful}/{len(all_results)} ({summary['success_rate']})")
        print(f"Total time: {summary['total_processing_time']}")
        print(f"Average per file: {summary['average_time_per_file']}")
        print(f"Results saved to: {target_dir}")
        if failed > 0:
            print(f"Failed files: {failed}")

if __name__ == "__main__":
    asyncio.run(main())
EOF
    
    chmod +x quick_process.py
    
    echo "✓ Quick setup complete!"
}

# Check model availability
check_models() {
    echo "Checking your model availability..."
    
    models=("qwen3:8b" "phi4-reasoning:14b" "mistral-nemo:12b" "qwen3-coder:30b" "hermes3:8b" "ingu627/phi-4-mini-instruct-q4:latest")
    
    for model in "${models[@]}"; do
        if ollama list | grep -q "$model"; then
            echo "✓ $model - Available"
        else
            echo "⚠ $model - Not found (will need to download)"
        fi
    done
    echo
}

# Enhanced server status check
check_servers_status() {
    local gtx_ok=false
    local quadro_ok=false
    
    echo "Testing server connectivity..."
    
    # Try multiple times with timeout
    for i in {1..5}; do
        curl -s --connect-timeout 5 http://localhost:11434/api/tags > /dev/null && gtx_ok=true
        curl -s --connect-timeout 5 http://localhost:11435/api/tags > /dev/null && quadro_ok=true
        
        if $gtx_ok && $quadro_ok; then
            break
        fi
        echo "  Attempt $i/5..."
        sleep 2
    done
    
    if $gtx_ok; then 
        echo "✓ GTX 1060 server ready (port 11434)"
    else 
        echo "✗ GTX 1060 server failed to start or respond"
        if [ -f gtx1060.log ]; then
            echo "  Check gtx1060.log for details"
        fi
    fi
    
    if $quadro_ok; then 
        echo "✓ Quadro P4000 server ready (port 11435)"
    else 
        echo "✗ Quadro P4000 server failed to start or respond"
        if [ -f quadro.log ]; then
            echo "  Check quadro.log for details"
        fi
    fi
}

# Improved server startup with better process management
start_dual_servers() {
    echo "Starting dual GPU Ollama servers..."
    
    # Stop any existing servers first
    echo "Stopping any existing servers..."
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 3
    
    # Clean up old log files and PIDs
    rm -f gtx1060.pid quadro.pid gtx1060.log quadro.log
    
    # Start GTX 1060 server with proper logging
    echo "Starting GTX 1060 server (port 11434)..."
    nohup bash -c "CUDA_VISIBLE_DEVICES=0 ollama serve" > gtx1060.log 2>&1 &
    GTX_PID=$!
    echo $GTX_PID > gtx1060.pid
    
    # Start Quadro P4000 server with proper logging  
    echo "Starting Quadro P4000 server (port 11435)..."
    nohup bash -c "CUDA_VISIBLE_DEVICES=1 OLLAMA_HOST=0.0.0.0:11435 ollama serve" > quadro.log 2>&1 &
    QUADRO_PID=$!
    echo $QUADRO_PID > quadro.pid
    
    # Wait for servers to initialize
    echo "Waiting for servers to initialize..."
    sleep 8
    
    check_servers_status
    
    echo
    echo "Server logs available:"
    echo "  GTX 1060: gtx1060.log"
    echo "  Quadro P4000: quadro.log"
}

# Pre-flight check before processing
check_servers_before_processing() {
    echo "Checking server status before processing..."
    
    local gtx_ok=false
    local quadro_ok=false
    
    curl -s --connect-timeout 3 http://localhost:11434/api/tags > /dev/null && gtx_ok=true
    curl -s --connect-timeout 3 http://localhost:11435/api/tags > /dev/null && quadro_ok=true
    
    if ! $gtx_ok; then
        echo "⚠ GTX 1060 server not responding."
        read -p "Start servers now? (y/N): " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            start_dual_servers
            return $?
        else
            echo "Cannot process without servers. Exiting."
            exit 1
        fi
    fi
    
    if ! $quadro_ok; then
        echo "⚠ Quadro P4000 server not responding, but GTX 1060 is available."
        echo "You can still use the GTX 1060 for processing."
    fi
    
    return 0
}

# Run quick demo
demo() {
    echo "Running quick demo..."
    
    # Create sample documents
    mkdir -p demo_docs
    
    cat > demo_docs/sample.txt << 'EOF'
The Dell Precision T3600 is a powerful workstation designed for professional applications.
It features Intel Xeon processors and can support multiple NVIDIA GPUs for parallel processing.
This makes it excellent for AI/ML workloads and document processing with language models.
EOF
    
    cat > demo_docs/code_sample.py << 'EOF'
def process_documents(directory, model_name):
    """Process all documents in a directory using specified model"""
    files = os.listdir(directory)
    results = []
    
    for file in files:
        if file.endswith('.txt'):
            content = read_file(file)
            result = llm_process(content, model_name)
            results.append(result)
    
    return results
EOF
    
    echo "Created demo documents:"
    ls -la demo_docs/
    
    echo
    echo "Processing with qwen3:8b..."
    python3 quick_process.py demo_docs demo_results "Provide a brief summary and key points"
    
    if [ -d demo_results ]; then
        echo
        echo "Demo results:"
        ls -la demo_results/
        
        echo
        echo "Sample output:"
        if [ -f demo_results/sample_result.json ]; then
            echo "File: sample.txt"
            jq -r '.response' demo_results/sample_result.json | head -3
        fi
    fi
}

# Main menu
echo "What would you like to do?"
echo
echo "1. Quick Setup (30 seconds)"
echo "2. Check Models & Start Servers"
echo "3. Run Demo"
echo "4. Process My Documents (Enhanced)"
echo "5. Check GPU Status"
echo "6. Stop Servers"
echo "7. View Server Logs"
echo "8. Get Full Setup (advanced)"
echo

read -p "Choose (1-8): " choice

case $choice in
    1)
        quick_setup
        check_models
        echo
        echo "Setup complete! Next steps:"
        echo "  2. Check models & start servers"  
        echo "  3. Run demo to test"
        echo "  4. Process your documents"
        ;;
    
    2)
        check_models
        start_dual_servers
        echo
        echo "Servers ready! Now you can:"
        echo "  - Run demo (option 3)"
        echo "  - Process documents (option 4)"
        ;;
    
    3)
        if [ ! -f quick_process.py ]; then
            echo "Run quick setup first (option 1)"
            exit 1
        fi
        
        check_servers_before_processing
        demo
        ;;
    
    4)
        if [ ! -f quick_process.py ]; then
            echo "Run quick setup first (option 1)"
            exit 1
        fi
        
        check_servers_before_processing
        
        echo
        read -p "Source directory: " source_dir
        read -p "Target directory: " target_dir
        read -p "Processing prompt: " prompt
        
        if [ ! -d "$source_dir" ]; then
            echo "Directory $source_dir not found!"
            exit 1
        fi
        
        echo
        echo "Model options:"
        echo "  1 - qwen3:8b (Quality - Quadro P4000)"
        echo "  2 - phi4-reasoning:14b (Reasoning - Quadro P4000)" 
        echo "  3 - qwen3-coder:30b (Coding - Quadro P4000)"
        echo "  4 - hermes3:8b (Balanced - GTX 1060)"
        echo "  5 - phi-4-mini (Fast - GTX 1060)"
        echo "  auto - Smart selection based on file type"
        read -p "Choose model [auto]: " model_choice
        model_choice=${model_choice:-auto}
        
        python3 quick_process.py "$source_dir" "$target_dir" "$prompt" "$model_choice"
        
        # Show summary if available
        if [ -f "$target_dir/processing_summary.json" ]; then
            echo
            echo "Processing Summary:"
            python3 -c "
import json
with open('$target_dir/processing_summary.json') as f:
    summary = json.load(f)
print(f\"  Files: {summary['successful']}/{summary['total_files']} ({summary['success_rate']})\")
print(f\"  Time: {summary['total_processing_time']} (avg: {summary['average_time_per_file']})\")
print(f\"  Models: {', '.join(summary['models_used'])}\")
"
        fi
        ;;
    
    5)
        echo "=== T3600 System Status ==="
        echo
        echo "GPU Status:"
        if command -v nvidia-smi > /dev/null; then
            nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits | while IFS=',' read gpu name util mem_used mem_total temp; do
                printf "  GPU%s %-20s %2s%% %4sMB/%4sMB %2s°C\n" "$gpu" "$name" "$util" "$mem_used" "$mem_total" "$temp"
            done
        else
            echo "  nvidia-smi not available"
        fi
        echo
        echo "Ollama Servers:"
        curl -s --connect-timeout 3 http://localhost:11434/api/tags > /dev/null && echo "  ✓ GTX 1060 (port 11434): Online" || echo "  ✗ GTX 1060: Offline"
        curl -s --connect-timeout 3 http://localhost:11435/api/tags > /dev/null && echo "  ✓ Quadro P4000 (port 11435): Online" || echo "  ✗ Quadro P4000: Offline"
        
        echo
        echo "Active Ollama Processes:"
        ps aux | grep -E "ollama serve" | grep -v grep | while read line; do
            pid=$(echo $line | awk '{print $2}')
            cpu=$(echo $line | awk '{print $3}')
            mem=$(echo $line | awk '{print $4}')
            echo "  PID: $pid, CPU: $cpu%, MEM: $mem%"
        done || echo "  No Ollama processes running"
        ;;
    
    6)
        echo "Stopping servers..."
        if [ -f gtx1060.pid ]; then
            kill $(cat gtx1060.pid) 2>/dev/null && echo "✓ GTX 1060 server stopped"
            rm -f gtx1060.pid
        fi
        
        if [ -f quadro.pid ]; then
            kill $(cat quadro.pid) 2>/dev/null && echo "✓ Quadro P4000 server stopped"
            rm -f quadro.pid
        fi
        
        # Kill any remaining ollama processes
        pkill -f "ollama serve" 2>/dev/null && echo "✓ All Ollama processes stopped" || echo "No additional processes found"
        ;;
    
    7)
        echo "=== Server Logs ==="
        
        if [ -f gtx1060.log ]; then
            echo
            echo "GTX 1060 Server Log (last 20 lines):"
            tail -n 20 gtx1060.log
        else
            echo "No GTX 1060 log file found"
        fi
        
        if [ -f quadro.log ]; then
            echo
            echo "Quadro P4000 Server Log (last 20 lines):"
            tail -n 20 quadro.log
        else
            echo "No Quadro P4000 log file found"
        fi
        
        echo
        echo "Log files: gtx1060.log, quadro.log"
        ;;
    
    8)
        echo "For the complete advanced setup with full features:"
        echo
        echo "Advanced features include:"
        echo "  - PDF/DOCX/Image processing with OCR"
        echo "  - Advanced batch processing with Robert McDermott's cluster tools"
        echo "  - Performance monitoring dashboard"
        echo "  - Result merging and analysis tools"
        echo "  - Model optimization recommendations"
        echo "  - Integration with LangChain for RAG workflows"
        echo
        echo "To get the full setup:"
        echo "  1. Download the complete processor: existing_setup_processor.sh"
        echo "  2. Run: ./existing_setup_processor.sh"
        echo "  3. Choose option 8: 'Complete automated setup'"
        echo
        echo "The full setup builds on this quick start and adds enterprise-grade features."
        ;;
    
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo
echo "Quick Start Complete!"
echo
echo "Your T3600 models perfect for different tasks:"
echo "  • qwen3:8b - General high-quality processing"
echo "  • qwen3-coder:30b - Code analysis and programming"  
echo "  • phi4-reasoning:14b - Complex reasoning tasks"
echo "  • mistral-nemo:12b - Advanced instruction following"
echo "  • phi-4-mini - Fast processing for simple tasks"
