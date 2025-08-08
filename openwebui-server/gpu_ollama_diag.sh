#!/usr/bin/env bash
set -euo pipefail

banner(){ printf "\n==== %s ====\n" "$*"; }
ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
err(){ echo "❌ $*"; }

banner "SYSTEM / GPU BASICS"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
  ok "nvidia-smi works"
else
  err "nvidia-smi not found (install NVIDIA driver/tooling)"
fi

banner "KERNEL MODULES & /dev NODES"
lsmod | egrep -q '^nvidia ' && ok "nvidia kernel module loaded" || err "nvidia module missing"
lsmod | egrep -q '^nvidia_uvm ' && ok "nvidia_uvm loaded" || warn "nvidia_uvm not loaded (modprobe nvidia_uvm)"
if ls -l /dev/nvidiactl /dev/nvidia0 1>/dev/null 2>&1; then
  ls -l /dev/nvidia*
  ok "/dev/nvidia* nodes exist"
else
  err "/dev/nvidia* device nodes missing (run: sudo nvidia-modprobe -u -c=0)"
fi

banner "CUDA DRIVER LIBS"
if ldconfig -p | grep -q 'libcuda\.so'; then
  ldconfig -p | grep -E 'libcuda\.so|libnvidia-ml\.so'
  ok "CUDA driver libs present in linker cache"
else
  err "libcuda.so not in ldconfig (driver install incomplete?)"
fi
ldconfig -p | grep -qi libcublas.so && ok "libcublas present" || warn "libcublas missing (sudo apt install libcublas12)"

banner "cuInit PROBE (Python -> libcuda.so)"
python3 - <<'PY' || true
import ctypes, sys
try:
    cuda=ctypes.CDLL('libcuda.so')
    cuInit=cuda.cuInit; cuInit.argtypes=[ctypes.c_uint]; cuInit.restype=ctypes.c_int
    cuDeviceGetCount=cuda.cuDeviceGetCount; cuDeviceGetCount.argtypes=[ctypes.POINTER(ctypes.c_int)]; cuDeviceGetCount.restype=ctypes.c_int
    rc=cuInit(0); print("cuInit rc:",rc)
    if rc==0:
        n=ctypes.c_int(0); rc2=cuDeviceGetCount(ctypes.byref(n))
        print("cuDeviceGetCount rc:", rc2, "count:", n.value)
except Exception as e:
    print("EXC:", e); sys.exit(0)
PY

banner "OLLAMA PROCESS & PORT"
pgrep -fa 'ollama serve' || warn "no foreground ollama serve"
sudo ss -lptn 'sport = :11434' || true
sudo lsof -i :11434 || true

banner "OLLAMA SERVICE ENV & DEVICE ACCESS"
if systemctl is-enabled --quiet ollama 2>/dev/null; then
  systemctl show ollama | grep -E 'Environment=|DeviceAllow=' || true
  ok "showed ollama env; verify CUDA_VISIBLE_DEVICES/OLLAMA_SCHED_SPREAD"
else
  warn "ollama systemd unit not enabled"
fi

banner "OLLAMA API & GPU INIT"
if curl -sf http://127.0.0.1:11434/api/version >/dev/null; then
  ok "Ollama API reachable"
  # small nudge to force init without spamming
  curl -s -m 3 http://127.0.0.1:11434/api/generate \
    -H 'content-type: application/json' \
    -d '{"model":"qwen3:14b","prompt":" . ","stream":false,"options":{"num_predict":1}}' >/dev/null || true
else
  warn "Ollama API not responding on 11434"
fi

banner "GPU USAGE BY OLLAMA"
if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi --query-compute-apps=pid,process_name,gpu_uuid,used_memory --format=csv,noheader 2>/dev/null | grep -i ollama; then
    ok "Ollama is on GPU (compute process present)"
  else
    warn "Ollama not on GPU right now (idle or CPU fallback)"
  fi
fi

banner "SUGGESTED FIXES (if problems found)"
cat <<'TIP'
- If CUDA init shows 999/unknown: check /dev/nvidia* exist & perms; ensure correct libcuda.so; restart service.
- If only one GPU is used:
  * Add to service: OLLAMA_SCHED_SPREAD=true
  * Ensure DeviceAllow includes /dev/nvidia0 and /dev/nvidia1
  * Set CUDA_VISIBLE_DEVICES=0,1 (bigger VRAM first)
- If 11434 already in use: stop stray process or systemd unit then restart.
TIP
