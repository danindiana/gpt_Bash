#!/bin/bash

# Quick Fix Toolkit for Common OpenWebUI Issues
# One-command solutions for frequent problems

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Common service names
OPENWEBUI_SERVICE="openwebui"
DOMAIN="ryleh-openweb.duckdns.org"

restart_stack() {
    log "Restarting entire OpenWebUI stack..."
    
    log "Stopping services..."
    sudo systemctl stop $OPENWEBUI_SERVICE || warning "OpenWebUI already stopped"
    sudo systemctl stop ollama || warning "Ollama already stopped"
    
    log "Starting Ollama..."
    sudo systemctl start ollama
    sleep 3
    
    log "Starting OpenWebUI..."
    sudo systemctl start $OPENWEBUI_SERVICE
    sleep 5
    
    log "Restarting Nginx..."
    sudo systemctl restart nginx
    
    success "Stack restart complete"
    
    # Quick health check
    if curl -s http://localhost:5000 >/dev/null; then
        success "OpenWebUI responding locally"
    else
        error "OpenWebUI not responding - check logs"
    fi
}

fix_permissions() {
    log "Fixing common permission issues..."
    
    local data_dir="/var/lib/open-webui"
    local venv_dir="/home/randy/programs/py_progs/openwebui"
    
    if [[ -d "$data_dir" ]]; then
        log "Fixing data directory permissions..."
        sudo chown -R randy:randy "$data_dir"
        sudo chmod -R 755 "$data_dir"
        success "Data directory permissions fixed"
    fi
    
    if [[ -d "$venv_dir" ]]; then
        log "Fixing virtual environment permissions..."
        sudo chown -R randy:randy "$venv_dir"
        success "Virtual environment permissions fixed"
    fi
    
    log "Fixing service file permissions..."
    sudo chmod 644 /etc/systemd/system/$OPENWEBUI_SERVICE.service*
    sudo systemctl daemon-reload
    success "Service permissions fixed"
}

clear_cache() {
    log "Clearing caches and temporary files..."
    
    # Python cache
    find /home/randy/programs/py_progs/openwebui -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find /home/randy/programs/py_progs/openwebui -name "*.pyc" -delete 2>/dev/null || true
    
    # Pip cache
    /home/randy/programs/py_progs/openwebui/venv/bin/pip cache purge 2>/dev/null || true
    
    # System temp files
    sudo systemctl stop $OPENWEBUI_SERVICE
    rm -rf /tmp/openwebui* 2>/dev/null || true
    
    success "Caches cleared"
}

update_ssl() {
    log "Updating SSL certificate..."
    
    if sudo certbot renew --dry-run; then
        log "Running actual certificate renewal..."
        sudo certbot renew
        sudo systemctl restart nginx
        success "SSL certificate updated"
    else
        error "Certificate renewal failed - check configuration"
    fi
}

reset_networking() {
    log "Resetting network configuration..."
    
    # Restart networking components
    sudo systemctl restart systemd-resolved
    sudo systemctl restart nginx
    
    # Flush DNS
    sudo systemd-resolve --flush-caches
    
    # Test connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        success "External connectivity OK"
    else
        warning "No external connectivity"
    fi
    
    if nslookup $DOMAIN >/dev/null 2>&1; then
        success "DNS resolution OK"
    else
        warning "DNS resolution failed"
    fi
}

fix_cuda() {
    log "Attempting CUDA fix..."
    
    # Restart services that use CUDA
    sudo systemctl restart ollama
    sleep 3
    sudo systemctl restart $OPENWEBUI_SERVICE
    sleep 5
    
    # Test CUDA
    if nvidia-smi >/dev/null 2>&1; then
        success "NVIDIA drivers responding"
        
        # Test PyTorch CUDA
        local venv_python="/home/randy/programs/py_progs/openwebui/venv/bin/python"
        if $venv_python -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
            success "PyTorch CUDA working"
        else
            warning "PyTorch CUDA not working - may need reinstall"
        fi
    else
        error "NVIDIA drivers not responding"
    fi
}

check_logs() {
    log "Checking recent error logs..."
    
    echo
    log "OpenWebUI errors (last 20 lines):"
    journalctl -u $OPENWEBUI_SERVICE --no-pager -n 20 | grep -i "error\|exception\|failed" || echo "No recent errors"
    
    echo
    log "Nginx errors (last 10 lines):"
    sudo tail -10 /var/log/nginx/error.log 2>/dev/null | grep -v "^\s*$" || echo "No recent errors"
    
    echo
    log "System errors (last 10 lines):"
    journalctl --no-pager -p err -n 10 --since "1 hour ago" || echo "No recent system errors"
}

full_diagnostics() {
    log "Running full diagnostic suite..."
    
    # Use the main diagnostic script if available
    if [[ -f "./openwebui_diagnostics.sh" ]]; then
        ./openwebui_diagnostics.sh
    else
        # Basic checks
        log "Service status:"
        systemctl status $OPENWEBUI_SERVICE --no-pager -l || true
        
        echo
        log "Port availability:"
        ss -tlnp | grep -E ":(80|443|5000|11434)" || echo "No relevant ports listening"
        
        echo
        log "Basic connectivity:"
        curl -s -o /dev/null -w "Local OpenWebUI: %{http_code}\n" http://localhost:5000 || echo "Local connection failed"
        curl -s -o /dev/null -w "External HTTPS: %{http_code}\n" https://$DOMAIN || echo "External connection failed"
    fi
}

emergency_recovery() {
    warning "Running emergency recovery procedure..."
    
    log "1. Stopping all services..."
    sudo systemctl stop $OPENWEBUI_SERVICE || true
    sudo systemctl stop ollama || true
    sudo systemctl stop nginx || true
    
    log "2. Killing any hanging processes..."
    sudo pkill -f "open-webui" || true
    sudo pkill -f "ollama" || true
    
    log "3. Clearing temporary files..."
    clear_cache
    
    log "4. Fixing permissions..."
    fix_permissions
    
    log "5. Restarting services in order..."
    sudo systemctl start ollama
    sleep 5
    sudo systemctl start $OPENWEBUI_SERVICE
    sleep 5
    sudo systemctl start nginx
    
    log "6. Testing recovery..."
    sleep 10
    if curl -s http://localhost:5000 >/dev/null; then
        success "Emergency recovery successful"
    else
        error "Emergency recovery failed - manual intervention required"
        check_logs
    fi
}

show_help() {
    echo "OpenWebUI Quick Fix Toolkit"
    echo
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  restart     - Restart entire stack (ollama -> openwebui -> nginx)"
    echo "  permissions - Fix file and service permissions"
    echo "  cache       - Clear all caches and temporary files"
    echo "  ssl         - Update SSL certificate"
    echo "  network     - Reset networking components"
    echo "  cuda        - Fix CUDA/GPU issues"
    echo "  logs        - Check recent error logs"
    echo "  diagnose    - Run full diagnostic suite"
    echo "  emergency   - Emergency recovery (stops everything, cleans, restarts)"
    echo "  help        - Show this help"
    echo
    echo "Example: $0 restart"
}

main() {
    local comman
