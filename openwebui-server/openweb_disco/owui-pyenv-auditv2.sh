#!/usr/bin/env bash
# Inspect the Python/venv running Open WebUI and optionally open an activated subshell.

set -euo pipefail

header(){ printf "\n\033[1m%s\033[0m\n" "$1"; }
kv(){ printf "  - %-20s %s\n" "$1" "${2:-}"; }

# 0) Find a running Open WebUI process (pgrep first, then systemd)
PIDS="$(pgrep -a -f 'open-webui .*serve' || true)"
if [[ -z "${PIDS}" ]]; then
  svc="openwebui.service"
  if systemctl is-active --quiet "${svc}"; then
    pid="$(systemctl show -p MainPID --value "${svc}" 2>/dev/null || true)"
    [[ "${pid}" =~ ^[0-9]+$ && "${pid}" -gt 0 ]] && PIDS="$pid"
  fi
fi

header "Open WebUI Python Environment Audit"
if [[ -z "${PIDS}" ]]; then
  echo "No running 'open-webui serve' process found."
  echo "Tip: systemctl status openwebui.service"
  exit 1
fi

echo "Process candidates:"
echo "${PIDS}" | sed 's/^/  - /'

# Pick the first PID line's first field (works whether pgrep printed PID only or 'PID cmd...')
PID="$(echo "${PIDS}" | head -n1 | awk '{print $1}')"
header "Selected PID: ${PID}"

# 1) Basic process details
CMD="$(tr -d '\0' </proc/${PID}/cmdline | sed 's/\x0/ /g' || true)"
EXE="$(readlink -f /proc/${PID}/exe || true)"
CWD="$(readlink -f /proc/${PID}/cwd || true)"
USER="$(ps -o user= -p "${PID}" || true)"

kv "User" "$USER"
kv "Cmdline" "$CMD"
kv "exe" "$EXE"
kv "cwd" "$CWD"

# 2) Key environment vars from the running process
declare -A ENVV
if [[ -r "/proc/${PID}/environ" ]]; then
  while IFS= read -r -d '' kvp; do
    k="${kvp%%=*}"
    v="${kvp#*=}"
    # Only capture the keys we care about
    if [[ "$k" == "DATA_DIR"     || \
          "$k" == "DATABASE_URL" || \
          "$k" == "WEBUI_URL"    || \
          "$k" == "VIRTUAL_ENV"  || \
          "$k" == "PATH"         || \
          "$k" == "PYTHONPATH"   || \
          "$k" == "PYTHONHOME" ]]; then
      ENVV["$k"]="$v"
    fi
  done < /proc/${PID}/environ
fi

kv "VIRTUAL_ENV"  "${ENVV[VIRTUAL_ENV]:-(not set)}"
kv "DATA_DIR"     "${ENVV[DATA_DIR]:-(not set)}"
kv "DATABASE_URL" "${ENVV[DATABASE_URL]:-(not set)}"
kv "WEBUI_URL"    "${ENVV[WEBUI_URL]:-(not set)}"

# 3) Determine Python binary for this process/venv
PYBIN=""
if [[ -n "${ENVV[VIRTUAL_ENV]:-}" && -x "${ENVV[VIRTUAL_ENV]}/bin/python" ]]; then
  PYBIN="${ENVV[VIRTUAL_ENV]}/bin/python"
elif [[ -x "$EXE" ]]; then
  PYBIN="$EXE"
fi

if [[ -n "$PYBIN" ]]; then
  kv "Python bin" "$PYBIN"
  "$PYBIN" -V | awk '{print "  - Python version: " $0}'
else
  kv "Python bin" "(not detected)"
fi

# 4) Package & module inspection (run directly; no sudo gymnastics needed)
if [[ -n "$PYBIN" ]]; then
  echo
  echo "Python package context:"
  "$PYBIN" -m pip --no-color --disable-pip-version-check show open-webui 2>/dev/null || echo "  - open-webui: not installed via pip (or hidden)"

  echo
  echo "Module inspection (inside venv):"
  "$PYBIN" - <<'PY'
import sys, importlib, os
print('    site-packages paths (subset of sys.path):')
for p in sys.path:
    if 'site-packages' in p:
        print('     -', p)
try:
    m = importlib.import_module('open_webui')
    print('    open_webui module file:', os.path.abspath(m.__file__))
except Exception as e:
    print('    open_webui import FAILED:', e)
try:
    import lzma
    print('    lzma module: OK')
except Exception as e:
    print('    lzma module: MISSING (ensure liblzma-dev was present when building Python)')
PY
fi

# 5) Data/DB detection
header "Data & Database"

DATA_DIR="${ENVV[DATA_DIR]:-}"
if [[ -z "$DATA_DIR" ]]; then
  # Infer from open files if possible
  hits="$(ls -l /proc/${PID}/fd 2>/dev/null | awk '{print $NF}' | grep -E '/(webui\.db|vector_db/chroma\.sqlite3)$' || true)"
  if [[ -n "$hits" ]]; then
    first_hit="$(head -n1 <<<"$hits")"
    dir="$(dirname "$first_hit")"
    [[ "$dir" =~ /vector_db$ ]] && dir="$(dirname "$dir")"
    DATA_DIR="$dir"
  fi
fi

if [[ -n "$DATA_DIR" ]]; then
  kv "DATA_DIR (resolved)" "$DATA_DIR"
  [[ -f "$DATA_DIR/webui.db" ]] && kv "SQLite DB" "$DATA_DIR/webui.db"
  [[ -d "$DATA_DIR/vector_db" ]] && kv "Chroma DB dir" "$DATA_DIR/vector_db"
  [[ -d "$DATA_DIR/uploads"  ]] && kv "Uploads dir" "$DATA_DIR/uploads"
  [[ -f "$DATA_DIR/audit.log" ]] && kv "Audit log" "$DATA_DIR/audit.log"
  echo "  - Data dir contents (depth<=2):"
  (cd "$DATA_DIR" && find . -maxdepth 2 -mindepth 1 -printf "    %p\n" | head -n 50) || true
else
  echo "  - Could not resolve DATA_DIR from env or open files."
  echo "    Recommendation: set DATA_DIR explicitly in a systemd drop-in."
fi

echo "  - Open DB file handles (confirmation):"
(ls -l /proc/${PID}/fd 2>/dev/null | awk '{print $NF}' | grep -E '/(webui\.db|vector_db/chroma\.sqlite3)$' | sed 's/^/    /' || echo "    (none found)")

# 6) Offer interactive activation
header "Interactive activation"
if [[ -n "${ENVV[VIRTUAL_ENV]:-}" && -d "${ENVV[VIRTUAL_ENV]}/bin" ]]; then
  ACT="${ENVV[VIRTUAL_ENV]}/bin/activate"
  echo "To activate the same venv in THIS shell, copy/paste:"
  echo "    source '${ACT}'"
  echo
  read -r -p "Open a NEW subshell now with this venv activated? [y/N]: " ans
  if [[ "${ans:-}" =~ ^[Yy]$ ]]; then
    # Open a clean interactive subshell with the venv activated
    exec bash -i -c "source '${ACT}'; echo 'Venv activated in subshell. Type exit to return.'; exec bash -i"
  fi
else
  echo "No usable VIRTUAL_ENV detected; skipping activation."
fi

header "Summary"
echo "• PID:        ${PID}"
echo "• VENV:       ${ENVV[VIRTUAL_ENV]:-(none)}"
echo "• DATA_DIR:   ${DATA_DIR:-'(unknown)'}"
echo "• Python bin: ${PYBIN:-'(unknown)'}"
