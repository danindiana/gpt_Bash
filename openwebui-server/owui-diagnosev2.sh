#!/usr/bin/env bash
# Open WebUI launcher & config probe (expanded)
# Detects: launch method (systemd, native pip/venv, uvx/pipx, Docker/Podman),
# resolves DATA_DIR & DB path, extracts port, scans nginx, checks firewall,
# and prints actionable warnings.

set -euo pipefail

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
dim(){ printf "\033[2m%s\033[0m\n" "$*"; }
info(){ printf "  - %s\n" "$*"; }
warn(){ printf "\033[33m⚠ %s\033[0m\n" "$*"; }
ok(){ printf "\033[32m✓ %s\033[0m\n" "$*"; }
hr(){ printf "%s\n" "------------------------------------------------------------"; }
have(){ command -v "$1" >/dev/null 2>&1; }

print_header() {
  hr
  bold "Open WebUI Diagnostic Summary"
  date
  echo "Host  : $(hostnamectl --static 2>/dev/null || hostname)"
  if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "OS    : ${PRETTY_NAME:-$NAME $VERSION}"; fi
  echo "Kernel: $(uname -r)"
  hr
}

# ---------- helpers ----------
trim(){ sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# Extract value of --port N from a command line; default unknown
extract_port_from_cmd(){
  local line="$1"
  # --port N or --port=N
  if grep -q -- '--port[ =]' <<<"$line"; then
    sed -n 's/.*--port[ =]\([0-9]\+\).*/\1/p' <<<"$line" | head -n1
  elif grep -q -- '-p[ =]' <<<"$line"; then
    sed -n 's/.*-p[ =]\([0-9]\+\).*/\1/p' <<<"$line" | head -n1
  else
    echo ""
  fi
}

# Resolve DATA_DIR by priority:
# 1) running process environ
# 2) systemd unit Environment=DATA_DIR=...
# 3) working directory + /data
# 4) common paths: ~/.open-webui, /var/lib/open-webui
resolve_datadir(){
  local pid="$1" unit="$2" cwd="$3"
  local env_datadir=""
  if [[ -r "/proc/$pid/environ" ]]; then
    env_datadir="$(tr '\0' '\n' < /proc/$pid/environ | awk -F= '/^DATA_DIR=/{print $2; exit}')"
  fi
  if [[ -n "$env_datadir" && -d "$env_datadir" ]]; then
    echo "$env_datadir"; return 0
  fi

  local unit_datadir=""
  if [[ -n "$unit" ]] && have systemctl; then
    unit_datadir="$(systemctl cat "$unit" 2>/dev/null | awk -F= '/^\s*Environment=/{for(i=2;i<=NF;i++){if($i ~ /^DATA_DIR=/){sub(/^DATA_DIR=/,"",$i); print $i}}}' | tail -n1)"
  fi
  if [[ -n "$unit_datadir" && -d "$unit_datadir" ]]; then
    echo "$unit_datadir"; return 0
  fi

  if [[ -n "$cwd" && -d "$cwd/data" ]]; then
    echo "$cwd/data"; return 0
  fi

  if [[ -d "$HOME/.open-webui" ]]; then
    echo "$HOME/.open-webui"; return 0
  fi
  if [[ -d "/var/lib/open-webui" ]]; then
    echo "/var/lib/open-webui"; return 0
  fi
  echo ""  # unknown
}

# Pretty print db info if sqlite file exists
report_db_file(){
  local path="$1"
  if [[ -f "$path" ]]; then
    local size mtime
    size=$(stat -c '%s' "$path" 2>/dev/null || stat -f '%z' "$path")
    mtime=$(date -d "@$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path")" 2>/dev/null || stat -f '%Sm' "$path")
    ok "SQLite DB: $path"
    info "Size: ${size} bytes"
    info "Modified: $mtime"
  else
    warn "No SQLite DB at: $path"
  fi
}

print_header

# ---------- 1) process candidates ----------
bold "1) Process candidates"
mapfile -t CANDS < <(pgrep -af "open-webui|open_webui|uvx .*open-webui|python.*-m open_webui|gunicorn.*open_webui" || true)
if ((${#CANDS[@]}==0)); then
  warn "No obvious open-webui processes found by name."
else
  printf "%s\n" "${CANDS[@]}"
fi

# Pick the first candidate as the primary
PRIMARY_PID=""
PRIMARY_CMD=""
if ((${#CANDS[@]}>0)); then
  PRIMARY_PID="$(awk '{print $1}' <<<"${CANDS[0]}")"
  PRIMARY_CMD="$(cut -d' ' -f2- <<<"${CANDS[0]}")"
fi

# ---------- 2) systemd detection ----------
echo
bold "2) systemd unit(s)"
UNIT_LINES="$(systemctl list-units --type=service --no-pager 2>/dev/null | egrep -i 'open[-_]?webui' || true)"
if [[ -n "$UNIT_LINES" ]]; then
  echo "$UNIT_LINES"
  PRIMARY_UNIT="$(awk '{print $1; exit}' <<<"$UNIT_LINES")"
  echo
  bold "systemd status: $PRIMARY_UNIT"
  systemctl status "$PRIMARY_UNIT" --no-pager 2>/dev/null || true
  echo
  bold "systemd unit file (cat): $PRIMARY_UNIT"
  systemctl cat "$PRIMARY_UNIT" --no-pager 2>/dev/null | sed 's/^/    /' || true
else
  info "No open-webui* systemd services detected."
  PRIMARY_UNIT=""
fi

# Extract working dir, ExecStart and port from unit
UNIT_WD=""
UNIT_EXEC=""
UNIT_PORT=""
if [[ -n "$PRIMARY_UNIT" ]]; then
  UNIT_WD="$(systemctl show -p WorkingDirectory --value "$PRIMARY_UNIT" 2>/dev/null || true)"
  UNIT_EXEC="$(systemctl show -p ExecStart --value "$PRIMARY_UNIT" 2>/dev/null || true)"
  UNIT_PORT="$(extract_port_from_cmd "$UNIT_EXEC")"
fi

# ---------- 3) listening sockets ----------
echo
bold "3) Listening sockets"
if have ss; then
  ss -ltnp 2>/dev/null | awk 'NR==1 || /:([0-9]+)\s/ {print}'
elif have netstat; then
  netstat -ltnp 2>/dev/null || true
else
  warn "Neither ss nor netstat available."
fi

# ---------- 4) containers ----------
echo
bold "4) Containers (Docker/Podman)"
FOUND_CONT=0
if have docker; then
  docker ps --format '{{.ID}} {{.Image}} {{.Names}} {{.Status}}' | egrep -i 'open-webui' && FOUND_CONT=1 || true
fi
if have podman; then
  podman ps --format '{{.ID}} {{.Image}} {{.Names}} {{.Status}}' | egrep -i 'open-webui' && FOUND_CONT=1 || true
fi
(( FOUND_CONT==0 )) && info "No open-webui containers found."

# ---------- 5) env + data dir + database ----------
echo
bold "5) Environment, DATA_DIR & DB"
if [[ -n "$PRIMARY_PID" ]]; then
  ok "Primary PID: $PRIMARY_PID"
  dim "CMD: $PRIMARY_CMD"
  # selected env vars
  echo "Selected environment:"
  if [[ -r "/proc/$PRIMARY_PID/environ" ]]; then
    tr '\0' '\n' < "/proc/$PRIMARY_PID/environ" \
      | egrep '^(DATA_DIR|DATABASE_URL|ENABLE_PERSISTENT_CONFIG|WEBUI_URL|PORT|OLLAMA_API_BASE|OPENAI_API_BASE)=' \
      | sed 's/^/    /' || true
  else
    warn "Cannot read /proc/$PRIMARY_PID/environ (need sudo?)."
  fi

  # CWD
  CWD="$(readlink -f "/proc/$PRIMARY_PID/cwd" 2>/dev/null || true)"
  [[ -n "$CWD" ]] && info "Process CWD: $CWD"

  # Resolve DATA_DIR
  DATADIR="$(resolve_datadir "$PRIMARY_PID" "$PRIMARY_UNIT" "$CWD")"
  if [[ -n "$DATADIR" ]]; then
    ok "Resolved DATA_DIR: $DATADIR"
    [[ -d "$DATADIR/uploads" ]]   && info "uploads/: $DATADIR/uploads"
    [[ -d "$DATADIR/vector_db" ]] && info "vector_db/: $DATADIR/vector_db"
  else
    warn "Could not resolve DATA_DIR. (Default is ./data if not set.)"
  fi

  # DB detection
  DBURL="$(tr '\0' '\n' < "/proc/$PRIMARY_PID/environ" 2>/dev/null | awk -F= '/^DATABASE_URL=/{print $2; exit}')"
  if [[ -n "${DBURL:-}" ]]; then
    info "DATABASE_URL: $DBURL"
    if [[ "$DBURL" =~ ^sqlite ]]; then
      # try to parse sqlite file path after 'sqlite://'
      DBFILE="$(sed -n 's#^sqlite\+:\?//\(/\{0,1\}.*\)#\1#p' <<<"$DBURL" | head -n1)"
      [[ -n "$DBFILE" ]] && report_db_file "$DBFILE"
    else
      ok "External DB detected (non-sqlite)."
    fi
  else
    # assume sqlite default inside DATA_DIR
    if [[ -n "$DATADIR" ]]; then
      report_db_file "$DATADIR/webui.db"
    else
      warn "No DATABASE_URL and DATA_DIR unknown — cannot locate DB."
    fi
  fi
else
  warn "No running Open WebUI process found to read env/paths."
fi

# ---------- 6) Port derivation & quick probe ----------
echo
bold "6) Port check"
DERIVED_PORT=""
# Prefer unit-declared port
if [[ -n "$UNIT_PORT" ]]; then
  DERIVED_PORT="$UNIT_PORT"
fi
# Else try to parse from CMD
if [[ -z "$DERIVED_PORT" && -n "$PRIMARY_CMD" ]]; then
  DERIVED_PORT="$(extract_port_from_cmd "$PRIMARY_CMD")"
fi
# Else try common defaults
if [[ -z "$DERIVED_PORT" ]]; then
  # Scan for uvicorn bind in logs? As fallback, try 3000 then 5000
  DERIVED_PORT="5000"
fi
info "Derived/OpenWebUI port: ${DERIVED_PORT}"

if have curl; then
  echo
  info "HTTP probe (localhost:${DERIVED_PORT})"
  curl -sS -m 3 "http://127.0.0.1:${DERIVED_PORT}/_app/version.json" | head -c 300 || true
  echo
fi

# ---------- 7) nginx scan & mismatch warnings ----------
echo
bold "7) Nginx / reverse proxy scan"
NGX_LIVE_DIR="/etc/nginx/sites-enabled"
NGX_AVAIL_DIR="/etc/nginx/sites-available"
if [[ -d "$NGX_LIVE_DIR" || -d "$NGX_AVAIL_DIR" ]]; then
  # scan both active and backups for context
  grep -RInE 'listen\s+[0-9]+|proxy_pass\s+http' /etc/nginx 2>/dev/null | sed 's/^/  /' || true

  # Try to detect active proxy_pass targets
  ACTIVE_TARGETS="$(grep -RInE 'proxy_pass\s+http' "$NGX_LIVE_DIR" 2>/dev/null | awk '{print $0}')"
  if [[ -n "$ACTIVE_TARGETS" ]]; then
    echo
    bold "Active proxy targets:"
    echo "$ACTIVE_TARGETS" | sed 's/^/  /'
    if [[ -n "$DERIVED_PORT" ]]; then
      if ! grep -q ":${DERIVED_PORT}" <<<"$ACTIVE_TARGETS"; then
        warn "nginx proxy_pass does NOT reference port ${DERIVED_PORT}. You may be proxying to the wrong backend."
      else
        ok "nginx proxy_pass references the running port ${DERIVED_PORT}."
      fi
    fi
  else
    info "No active proxy_pass found in sites-enabled."
  fi
else
  info "nginx not installed or no site configs present."
fi

# ---------- 8) firewall ----------
echo
bold "8) Firewall"
if have ufw; then
  ufw status verbose 2>/dev/null | sed 's/^/  /' || true
else
  info "ufw not installed."
fi

# ---------- 9) Summary / Hints ----------
hr
bold "Summary"
if [[ -n "$PRIMARY_UNIT" ]]; then
  ok "Launch method: systemd unit '$PRIMARY_UNIT'"
elif [[ -n "$PRIMARY_PID" ]]; then
  ok "Launch method: foreground/native process (not systemd)"
else
  warn "Launch method unknown (no process seen)."
fi
if [[ -n "$DATADIR" ]]; then
  ok "DATA_DIR resolved: $DATADIR"
else
  warn "DATA_DIR not set; recommend setting it to avoid data loss on future changes."
fi
if [[ -n "$DERIVED_PORT" ]]; then
  ok "Open WebUI port: $DERIVED_PORT"
fi

hr
bold "Hints"
echo "  - Set DATA_DIR to a stable path to persist DB/files across upgrades. (See env config & quick start docs.)"
echo "  - If using nginx, ensure proxy_pass targets http://127.0.0.1:${DERIVED_PORT}/"
echo "  - For Postgres, set DATABASE_URL in the unit and migrate data."
hr
