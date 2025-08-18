#!/bin/bash

# OpenWebUI Diagnostic Suite
# Comprehensive health check for the entire stack

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OPENWEBUI_SERVICE="openwebui"
OPENWEBUI_PORT="5000"
NGINX_CONFIG="/etc/nginx/sites-available/openwebui-https.conf"
DOMAIN="ryleh-openweb.duckdns.org"

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

separator() {
    echo -e "${BLUE}$1${NC}"
    echo "=================================================="
}

# Test function with status tracking
test_component() {
    local name="$1"
    local test_cmd="$2"
    local expected="$3"
    
    printf "%-40s" "$name: "
    if eval "$test_cmd" >/dev/null 2>&1; then
        if [[ -n "$expected" ]]; then
            local result=$(eval "$test_cmd" 2>/dev/null)
            if [[ "$result" == *"$expected"* ]]; then
                success "OK"
                return 0
            else
                warning "UNEXPECTED ($result)"
                return 1
            fi
        else
            success "OK"
            return 0
        fi
    else
        error "FAILED"
        return 1
    fi
}

# Main diagnostic functions
check_system_health() {
    separator "SYSTEM HEALTH"
    
    test_component "System load" "uptime | cut -d',' -f3" ""
    test_component "Disk space (/)" "df / | tail -1 | awk '{print \$5}' | sed 's/%//'" ""
    test_component "Memory usage" "free -m | grep '^Mem:' | awk '{printf \"%.0f\", \$3/\$2*100}'" ""
    
    echo
    log "System Overview:"
    echo "  Load: $(uptime | cut -d',' -f3-5)"
    echo "  Disk: $(df -h / | tail -1 | awk '{print $4 " free of " $2}')"
    echo "  RAM:  $(free -h | grep '^Mem:' | awk '{print $3 " used of " $2}')"
}

check_nvidia_cuda() {
    separator "NVIDIA/CUDA STATUS"
    
    test_component "nvidia-smi available" "command -v nvidia-smi" ""
    test_component "CUDA devices detected" "nvidia-smi -L | wc -l" ""
    
    if command -v nvidia-smi >/dev/null 2>&1; then
        echo
        log "GPU Status:"
        nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu --format=csv,noheader,nounits | \
        while IFS=, read -r name mem_used mem_total temp util; do
            echo "  $name: ${mem_used}MB/${mem_total}MB, ${temp}°C, ${util}% util"
        done
        
        echo
        log "CUDA Version:"
        nvidia-smi | grep "CUDA Version" || echo "  CUDA version not detected"
    fi
}

check_ollama() {
    separator "OLLAMA STATUS"
    
    test_component "Ollama service running" "systemctl is-active ollama" "active"
    test_component "Ollama port listening" "ss -tlnp | grep :11434" ""
    test_component "Ollama API responding" "curl -s http://localhost:11434/api/tags" ""
    
    if systemctl is-active ollama >/dev/null 2>&1; then
        echo
        log "Ollama Models:"
        curl -s http://localhost:11434/api/tags 2>/dev/null | jq -r '.models[]?.name // "No models found"' 2>/dev/null || echo "  Unable to fetch model list"
        
        echo
        log "Ollama GPU Status:"
        if curl -s http://localhost:11434/api/ps 2>/dev/null | jq -e '.models[]' >/dev/null 2>&1; then
            echo "  Models currently loaded in memory"
        else
            echo "  No models currently loaded"
        fi
    fi
}

check_openwebui_service() {
    separator "OPENWEBUI SERVICE"
    
    test_component "Service status" "systemctl is-active $OPENWEBUI_SERVICE" "active"
    test_component "Service enabled" "systemctl is-enabled $OPENWEBUI_SERVICE" "enabled"
    test_component "Port $OPENWEBUI_PORT listening" "ss -tlnp | grep :$OPENWEBUI_PORT" ""
    test_component "Process running" "pgrep -f open-webui" ""
    
    echo
    log "Service Details:"
    if systemctl is-active $OPENWEBUI_SERVICE >/dev/null 2>&1; then
        echo "  Status: $(systemctl show $OPENWEBUI_SERVICE --property=ActiveState --value)"
        echo "  Uptime: $(systemctl show $OPENWEBUI_SERVICE --property=ActiveEnterTimestamp --value | cut -d' ' -f2-3)"
        echo "  Memory: $(systemctl show $OPENWEBUI_SERVICE --property=MemoryCurrent --value | numfmt --to=iec)"
    fi
    
    echo
    log "Environment Variables:"
    systemctl show $OPENWEBUI_SERVICE --property=Environment --value | tr ' ' '\n' | grep -E "^(WEBUI_|DATA_|CUDA_)" || echo "  No relevant env vars found"
}

check_python_environment() {
    separator "PYTHON ENVIRONMENT"
    
    local venv_path="/home/randy/programs/py_progs/openwebui/venv"
    
    test_component "Virtual environment exists" "test -d $venv_path" ""
    test_component "Python executable" "test -x $venv_path/bin/python" ""
    test_component "OpenWebUI package installed" "$venv_path/bin/pip list | grep -i open-webui" ""
    
    if [[ -d "$venv_path" ]]; then
        echo
        log "Python Environment Details:"
        echo "  Python: $($venv_path/bin/python --version)"
        echo "  Pip: $($venv_path/bin/pip --version | cut -d' ' -f1-2)"
        echo "  OpenWebUI: $($venv_path/bin/pip list | grep -i open-webui | awk '{print $2}' || echo 'Not found')"
        
        echo
        log "Key Dependencies:"
        $venv_path/bin/pip list | grep -E "(torch|transformers|fastapi|uvicorn)" | while read -r line; do
            echo "  $line"
        done
    fi
}

check_nginx() {
    separator "NGINX CONFIGURATION"
    
    test_component "Nginx service running" "systemctl is-active nginx" "active"
    test_component "Config file exists" "test -f $NGINX_CONFIG" ""
    test_component "Config syntax valid" "nginx -t" ""
    test_component "SSL certificate valid" "test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem" ""
    
    echo
    log "Nginx Status:"
    if systemctl is-active nginx >/dev/null 2>&1; then
        echo "  Version: $(nginx -v 2>&1 | cut -d'/' -f2)"
        echo "  Config test: $(nginx -t 2>&1 | tail -1)"
        
        echo
        log "Key Configuration Blocks:"
        if [[ -f "$NGINX_CONFIG" ]]; then
            echo "  Upstream: $(grep -c "upstream.*openwebui" $NGINX_CONFIG || echo 0) blocks"
            echo "  Locations: $(grep -c "location.*{" $NGINX_CONFIG || echo 0) blocks"
            echo "  WebSocket support: $(grep -c "proxy_set_header.*Upgrade" $NGINX_CONFIG || echo 0) instances"
        fi
    fi
}

check_networking() {
    separator "NETWORK CONNECTIVITY"
    
    test_component "Local OpenWebUI responds" "curl -s -o /dev/null -w '%{http_code}' http://localhost:$OPENWEBUI_PORT" "200"
    test_component "SSL certificate valid" "curl -s -k https://$DOMAIN >/dev/null" ""
    test_component "WebSocket endpoint" "curl -s -o /dev/null -w '%{http_code}' https://$DOMAIN/ws/socket.io/" ""
    
    echo
    log "Network Details:"
    echo "  External IP: $(curl -s https://ipinfo.io/ip || echo 'Unable to detect')"
    echo "  DNS resolution: $(dig +short $DOMAIN || echo 'Failed')"
    
    if command -v ss >/dev/null 2>&1; then
        echo
        log "Listening Ports:"
        ss -tlnp | grep -E ":(80|443|5000|11434)" | while read -r line; do
            echo "  $line"
        done
    fi
}

check_logs() {
    separator "RECENT LOG ANALYSIS"
    
    echo
    log "OpenWebUI Service Logs (last 10 lines):"
    journalctl -u $OPENWEBUI_SERVICE --no-pager -n 10 --since "1 hour ago" | tail -10 || echo "  No recent logs"
    
    echo
    log "Nginx Error Logs (last 5 lines):"
    tail -5 /var/log/nginx/error.log 2>/dev/null || echo "  No error log accessible"
    
    echo
    log "Recent WebSocket Activity:"
    journalctl -u $OPENWEBUI_SERVICE --no-pager --since "1 hour ago" | grep -i "socket\|ws" | tail -5 || echo "  No WebSocket activity"
}

generate_summary() {
    separator "DIAGNOSTIC SUMMARY"
    
    local issues=0
    
    echo
    log "Component Status Overview:"
    
    # Quick health checks
    if ! systemctl is-active $OPENWEBUI_SERVICE >/dev/null 2>&1; then
        error "OpenWebUI service is not running"
        ((issues++))
    fi
    
    if ! systemctl is-active nginx >/dev/null 2>&1; then
        error "Nginx is not running"
        ((issues++))
    fi
    
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        warning "NVIDIA drivers not detected"
        ((issues++))
    fi
    
    if ! curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        warning "Ollama API not responding"
        ((issues++))
    fi
    
    if ! curl -s http://localhost:$OPENWEBUI_PORT >/dev/null 2>&1; then
        error "OpenWebUI not responding locally"
        ((issues++))
    fi
    
    echo
    if [[ $issues -eq 0 ]]; then
        success "All major components appear healthy!"
    else
        warning "Found $issues potential issues requiring attention"
    fi
    
    echo
    log "Quick Fix Commands:"
    echo "  Restart OpenWebUI: sudo systemctl restart $OPENWEBUI_SERVICE"
    echo "  Restart Nginx: sudo systemctl restart nginx"
    echo "  Check GPU: nvidia-smi"
    echo "  View logs: journalctl -u $OPENWEBUI_SERVICE -f"
    echo "  Test local: curl http://localhost:$OPENWEBUI_PORT"
}

# Main execution
main() {
    echo "OpenWebUI Stack Diagnostic Suite"
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo
    
    check_system_health
    echo
    check_nvidia_cuda
    echo
    check_ollama
    echo
    check_openwebui_service
    echo
    check_python_environment
    echo
    check_nginx
    echo
    check_networking
    echo
    check_logs
    echo
    generate_summary
}

# Run diagnostics
main "$@"
