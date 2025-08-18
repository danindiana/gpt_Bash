#!/bin/bash

# CUDA/GPU Monitoring and Recovery Script
# Handles the mysterious CUDA dropouts you mentioned

set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "[$(date +'%H:%M:%S')] $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

check_cuda_health() {
    log "Checking CUDA/GPU health..."
    
    # Basic NVIDIA driver check
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        error "nvidia-smi not found - driver issue?"
        return 1
    fi
    
    # Check GPU accessibility
    if ! nvidia-smi -L >/dev/null 2>&1; then
        error "Cannot enumerate GPUs - driver crashed?"
        return 1
    fi
    
    local gpu_count=$(nvidia-smi -L | wc -l)
    success "Found $gpu_count GPU(s)"
    
    # Check for common CUDA issues
    local temp_issues=0
    local mem_issues=0
    
    nvidia-smi --query-gpu=temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits | \
    while IFS=, read -r temp mem_used mem_total; do
        if [[ ${temp%.*} -gt 85 ]]; then
            warning "GPU temperature high: ${temp}°C"
            ((temp_issues++))
        fi
        
        local mem_percent=$((mem_used * 100 / mem_total))
        if [[ $mem_percent -gt 95 ]]; then
            warning "GPU memory nearly full: ${mem_percent}%"
            ((mem_issues++))
        fi
    done
    
    # Check CUDA context
    if command -v python3 >/dev/null 2>&1; then
        log "Testing CUDA context creation..."
        if python3 -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPUs: {torch.cuda.device_count()}')" 2>/dev/null; then
            success "PyTorch CUDA context OK"
        else
            warning "PyTorch cannot access CUDA"
        fi
    fi
}

test_ollama_gpu() {
    log "Testing Ollama GPU utilization..."
    
    if ! systemctl is-active ollama >/dev/null 2>&1; then
        error "Ollama service not running"
        return 1
    fi
    
    # Check if models are using GPU
    local models_loaded=$(curl -s http://localhost:11434/api/ps | jq -r '.models[]?.name // empty' 2>/dev/null | wc -l)
    
    if [[ $models_loaded -eq 0 ]]; then
        log "No models loaded, loading test model..."
        # Load a small model to test GPU
        curl -s http://localhost:11434/api/generate -d '{"model":"llama3.2:1b","prompt":"test","stream":false}' >/dev/null 2>&1 &
        local curl_pid=$!
        
        sleep 5
        kill $curl_pid 2>/dev/null || true
        
        # Check GPU utilization during load
        local gpu_util=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
        if [[ ${gpu_util%.*} -gt 0 ]]; then
            success "GPU utilization detected: ${gpu_util}%"
        else
            warning "No GPU utilization during model load"
        fi
    else
        success "$models_loaded model(s) currently loaded"
    fi
}

cuda_recovery() {
    warning "Attempting CUDA recovery..."
    
    # Step 1: Restart Ollama (often fixes GPU context issues)
    log "Restarting Ollama service..."
    if sudo systemctl restart ollama; then
        success "Ollama restarted"
        sleep 3
    else
        error "Failed to restart Ollama"
    fi
    
    # Step 2: Clear GPU memory if possible
    log "Attempting to clear GPU memory..."
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --gpu-reset 2>/dev/null || warning "GPU reset not supported"
    fi
    
    # Step 3: Restart OpenWebUI if it's running
    if systemctl is-active openwebui >/dev/null 2>&1; then
        log "Restarting OpenWebUI service..."
        if sudo systemctl restart openwebui; then
            success "OpenWebUI restarted"
            sleep 5
        else
            error "Failed to restart OpenWebUI"
        fi
    fi
    
    # Step 4: Test recovery
    log "Testing recovery..."
    if check_cuda_health && test_ollama_gpu; then
        success "CUDA recovery appears successful"
        return 0
    else
        error "Recovery failed - may need driver reload"
        return 1
    fi
}

monitor_gpu() {
    log "Starting GPU monitoring (Ctrl+C to stop)..."
    
    while true; do
        clear
        echo "GPU Monitoring - $(date)"
        echo "=================================="
        
        nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu,utilization.memory --format=table
        
        echo
        echo "Ollama Status:"
        if curl -s http://localhost:11434/api/ps 2>/dev/null | jq -e '.models[]' >/dev/null 2>&1; then
            curl -s http://localhost:11434/api/ps | jq -r '.models[] | "  \(.name): \(.size_vram // "unknown") VRAM"' 2>/dev/null
        else
            echo "  No models loaded"
        fi
        
        echo
        echo "OpenWebUI Status: $(systemctl is-active openwebui 2>/dev/null)"
        
        sleep 5
    done
}

main() {
    case "${1:-check}" in
        "check")
            check_cuda_health
            test_ollama_gpu
            ;;
        "recover")
            cuda_recovery
            ;;
        "monitor")
            monitor_gpu
            ;;
        *)
            echo "Usage: $0 [check|recover|monitor]"
            echo "  check   - Check CUDA/GPU health (default)"
            echo "  recover - Attempt to recover from CUDA issues"
            echo "  monitor - Real-time GPU monitoring"
            ;;
    esac
}

main "$@"
