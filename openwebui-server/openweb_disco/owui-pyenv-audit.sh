#!/usr/bin/env bash
# Inspect the Python/venv that is running Open WebUI and summarize environment & data paths.
# Works for native/pip installs managed by systemd or foreground shells.

set -euo pipefail

header(){ printf "\n\033[1m%s\033[0m\n" "$1"; }
kv(){ printf "  - %-18s %s\n" "$1" "${2:-}"; }

# -- 0) Discover Open WebUI PIDs -------------------------------------------------
PIDS="$(pgrep -a -f 'open-webui( |$).*serve' || true)"
if [[ -z "${PIDS}" ]]; then
  # try systemd
  svc="openwebui.service"
  if systemctl is-active --quiet "${svc}"; then
    PIDS="$(systemctl show -p MainPID --value ${svc} | awk '$1>0{print $1}')"
  fi
fi

header "Open WebUI Python Environment Audit"
if [[ -z "${PIDS}" ]]; then
  echo "No running 'open-webui serve' process found."
  echo "Tip: Is the service running?  systemctl status openwebui.service"
  exit 1
fi

echo "Process candidates:"
echo "${PIDS}" | sed 's/^/  - /'

# Normalize into a list of PIDs (strip command args if present)
PID_LIST=()
while read -r line; do
  # lines may look like: "5756 /path/to/python ... open-webui serve"
  pid="$(awk '{print $1}' <<<"$line")"
  [[ "$pid" =~ ^[0-9]+$ ]] && PID_LIST+=("$pid")
done < <(printf "%s\n" "$PIDS")

# -- 1) For each PID, print Python/venv/env details ------------------------------
for PID in "${PID_LIST[@]}"; do
  header "PID $PID"

  # Basic process info
  CMD="$(tr -d '\0' </proc/${PID}/cmdline | sed 's/\x0/ /g' || true)"
  EXE="$(readlink -f /proc/${PID}/exe || true)"
  CWD="$(readlink -f /proc/${PID}/cwd || true)"
  USER="$(ps -o user= -p "${PID}" || true)"
  kv "User" "$USER"
  kv "Cmdline" "$CMD"
  kv "exe" "$EXE"
  kv "cwd" "$CWD"

  # Parse selected env vars from /proc/<pid>/environ
  # (These are the ones that matter most for Open WebUI runtime)
  declare -A ENVV
  while IFS= read -r -d '' kvp; do
    case "$kvp" in
      DATA_DIR=*|DATABASE_URL=*|WEBUI_URL=*|VIRTUAL_ENV=*|PATH=*|PYTHONPATH=*|PYTHONHOME=*)
        k="${kvp%%=*}"; v="${kvp#*=}"; ENVV["$k"]="$v"
      ;;
    esac
  done < /proc/${PID}/environ 2>/dev/null || true

  kv "VIRTUAL_ENV" "${ENVV[VIRTUAL_ENV]:-}"
  kv "DATA_DIR"    "${ENVV[DATA_DIR]:-}"
  kv "DATABASE_URL" "${ENVV[DATABASE_URL]:-}"
  kv "WEBUI_URL"   "${ENVV[WEBUI_URL]:-}"

  # Detect Python & venv
  PYBIN=""
  if [[ -n "${ENVV[VIRTUAL_ENV]:-}" && -x "${ENVV[VIRTUAL_ENV]}/bin/python" ]]; then
    PYBIN="${ENVV[VIRTUAL_ENV]}/bin/python"
  elif [[ -x "$EXE" ]]; then
    PYBIN="$EXE"
  fi

  if [[ -z "$PYBIN" ]]; then
    kv "Python" "Unknown (could not resolve)"
  else
    kv "Python bin" "$PYBIN"
    "$PYBIN" -V 2>&1 | awk '{print "  - Python version      " $0}'
  fi

  # Pip/open-webui package info (run as the same user)
  if [[ -n "$PYBIN" ]]; then
    sudo -u "$USER" -g "$USER" bash -lc "
      '$PYBIN' -m pip --version 2>/dev/null && \
      '$PYBIN' -m pip show open-webui 2>/dev/null | sed 's/^/    /'
    " || true
  fi

  # Site-packages & open_webui import location
  if [[ -n "$PYBIN" ]]; then
    sudo -u "$USER" -g "$USER" bash -lc "
      '$PYBIN' - <<'PY'
import sys, site, importlib, os
print('    site-packages:')
paths = []
try:
  paths = site.getsitepackages()
except Exception:
  pass
if not paths:
  paths = [p for p in sys.path if p.endswith('site-packages')]
for p in dict.fromkeys(paths):
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
  print('    lzma module: MISSING -> ensure liblzma-dev was present at build time')
PY
    " || true
  fi

  # -- 2) Data/DB detection ------------------------------------------------------
  header "Data & Database (PID $PID)"

  # Prefer explicit DATA_DIR; otherwise try to infer via open files (webui.db/chroma)
  DATA_DIR="${ENVV[DATA_DIR]:-}"
  if [[ -z "$DATA_DIR" ]]; then
    # Try to infer by looking at open SQLite/Chroma files
    hits="$(ls -l /proc/${PID}/fd 2>/dev/null | awk '{print $NF}' | grep -E '/(webui\.db|vector_db/chroma\.sqlite3)$' || true)"
    if [[ -n "$hits" ]]; then
      # strip filename -> dir
      DATA_DIR="$(dirname "$(head -n1 <<<"$hits")")"
      # if we matched webui.db, its dir is the DATA_DIR; if vector_db, take parent dir
      if [[ "$DATA_DIR" =~ /vector_db$ ]]; then DATA_DIR="$(dirname "$DATA_DIR")"; fi
    fi
  fi

  if [[ -n "$DATA_DIR" ]]; then
    kv "DATA_DIR (resolved)" "$DATA_DIR"
    [[ -f "$DATA_DIR/webui.db" ]] && kv "SQLite DB" "$DATA_DIR/webui.db"
    [[ -d "$DATA_DIR/vector_db" ]] && kv "Chroma DB dir" "$DATA_DIR/vector_db"
    [[ -d "$DATA_DIR/uploads" ]] && kv "Uploads dir" "$DATA_DIR/uploads"
    [[ -f "$DATA_DIR/audit.log" ]] && kv "Audit log" "$DATA_DIR/audit.log"

    echo "  - Data dir (top-level, depth<=2):"
    (cd "$DATA_DIR" && find . -maxdepth 2 -mindepth 1 -printf "    %p\n" | head -n 50) || true
  else
    echo "  - Could not resolve DATA_DIR from env or open files."
    echo "    Note: Open WebUI recommends explicitly setting DATA_DIR to avoid data loss. See docs."
  fi

  # Open files pointing at DBs (extra confirmation)
  echo "  - Open DB file handles:"
  (ls -l /proc/${PID}/fd 2>/dev/null | awk '{print $NF}' | grep -E '/(webui\.db|vector_db/chroma\.sqlite3)$' | sed 's/^/    /' || echo "    (none found)")

  # Light SQLite sanity (only if sqlite3 exists & DB is readable)
  if command -v sqlite3 >/dev/null 2>&1 && [[ -n "$DATA_DIR" && -f "$DATA_DIR/webui.db" ]]; then
    echo "  - SQLite PRAGMA integrity_check (snippet):"
    sqlite3 "$DATA_DIR/webui.db" "PRAGMA quick_check;" | sed 's/^/    /' || true
  fi

done

header "Notes"
echo "• DATA_DIR is the persistent store; setting it explicitly is recommended. (docs: env-config / quick-start)"
echo "• Typical contents under DATA_DIR: webui.db, uploads/, vector_db/, cache/, audit.log."
echo "• DATABASE_URL can switch from SQLite to Postgres; WEBUI_URL should match your public URL if proxied."
