#!/usr/bin/env bash
# Open WebUI launcher & config probe (v3.1)
# Adds: DB auto-locate when DATA_DIR unset, lsof socket check, small robustness tweaks.

set -euo pipefail

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
dim(){ printf "\033[2m%s\033[0m\n" "$*"; }
info(){ printf "  - %s\n" "$*"; }
warn(){ printf "\033[33m⚠ %s\033[0m\n" "$*"; }
ok(){ printf "\033[32m✓ %s\033[0m\n" "$*"; }
hr(){ printf "%s\n" "------------------------------------------------------------"; }
have(){ command -v "$1" >/dev/null 2>&1; }

extract_port_from_cmd(){
  local line="$1"
  if grep -q -- '--port[ =]' <<<"$line"; then
    sed -n 's/.*--port[ =]\([0-9]\+\).*/\1/p' <<<"$line" | head -n1
  elif grep -q -- '-p[ =]' <<<"$line"; then
    sed -n 's/.*-p[ =]\([0-9]\+\).*/\1/p' <<<"$line" | head -n1
  else
    echo ""
  fi
}

resolve_unit_name(){
  systemctl list-units --type=service --no-legend 2>/dev/null \
    | awk '/open[-_]?webui/{print $1; exit}'
}

# Priority: proc env -> unit env -> $cwd/data -> ~/.open-webui -> /var/lib/open-webui
resolve_datadir(){
  local pid="$1" unit="$2" cwd="$3"
  local env_datadir unit_datadir
  [[ -r "/proc/$pid/environ" ]] && env_datadir="$(tr '\0' '\n' < /proc/$pid/environ | awk -F= '/^DATA_DIR=/{print $2; exit}')"
  if [[ -n "$env_datadir" && -d "$env_datadir" ]]; then echo "$env_datadir"; return; fi
  if [[ -n "$unit" ]]; then
    unit_datadir="$(systemctl cat "$unit" 2>/dev/null | awk -F= '/^\s*Environment=/{for(i=2;i<=NF;i++){if($i ~ /^DATA_DIR=/){sub(/^DATA_DIR=/,"",$i); print $i}}}' | tail -n1)"
    [[ -n "$unit_datadir" && -d "$unit_datadir" ]] && { echo "$unit_datadir"; return; }
  fi
  [[ -n "$cwd" && -d "$cwd/data" ]] && { echo "$cwd/data"; return; }
  [[ -d "$HOME/.open-webui" ]] && { echo "$HOME/.open-webui"; return; }
  [[ -d "/var/lib/open-webui" ]] && { echo "/var/lib/open-webui"; return; }
  echo ""
}

report_db_file(){
  local path="$1"
  if [[ -f "$path" ]]; then
    local size mtime
    if stat --version >/dev/null 2>&1; then
      size=$(stat -c '%s' "$path")
      mtime=$(date -d "@$(stat -c '%Y' "$path")")
    else
      size=$(stat -f '%z' "$path")
      mtime=$(stat -f '%Sm' "$path")
    fi
    ok "SQLite DB: $path"
    info "Size: ${size} bytes"
    info "Modified: $mtime"
  else
    warn "No SQLite DB at: $path"
  fi
}

# ---- Header
hr; bold "Open WebUI Diagnostic Summary"
date
echo "Host  : $(hostnamectl --static 2>/dev/null || hostname)"
if [[ -r /etc/os-release ]]; then . /etc/os-release; echo "OS    : ${PRETTY_NAME:-$NAME $VERSION}"; fi
echo "Kernel: $(uname -r)"
hr

# ---- 1) Process candidates
bold "1) Process candidates"
mapfile -t CANDS < <(pgrep -af "open-webui|open_webui|uvx .*open-webui|python.*-m open_webui|gunicorn.*open_webui" || true)
if ((${#CANDS[@]}==0)); then warn "No obvious open-webui processes found by name."; else printf "%s\n" "${CANDS[@]}"; fi
PRIMARY_PID=""; PRIMARY_CMD=""
if ((${#CANDS[@]}>0)); then
  PRIMARY_PID="$(awk '{print $1}' <<<"${CANDS[0]}")"
  PRIMARY_CMD="$(cut -d' ' -f2- <<<"${CANDS[0]}")"
fi

# ---- 2) systemd
echo; bold "2) systemd unit(s)"
PRIMARY_UNIT="$(resolve_unit_name || true)"
if [[ -n "$PRIMARY_UNIT" ]]; then
  systemctl list-units --type=service --no-pager 2>/dev/null | awk '/open[-_]?webui/ {print}'
  echo; bold "systemd status: $PRIMARY_UNIT"
  systemctl status "$PRIMARY_UNIT" --no-pager 2>/dev/null || true
  echo; bold "systemd unit file (cat): $PRIMARY_UNIT"
  systemctl cat "$PRIMARY_UNIT" --no-pager 2>/dev/null | sed 's/^/    /' || true
else
  info "No open-webui* systemd services detected."
fi
UNIT_WD=""; UNIT_EXEC=""; UNIT_PORT=""
if [[ -n "$PRIMARY_UNIT" ]]; then
  UNIT_WD="$(systemctl show -p WorkingDirectory --value "$PRIMARY_UNIT" 2>/dev/null || true)"
  UNIT_EXEC="$(systemctl show -p ExecStart --value "$PRIMARY_UNIT" 2>/dev/null || true)"
  UNIT_PORT="$(extract_port_from_cmd "$UNIT_EXEC")"
fi

# ---- 3) Listening sockets (ss + lsof)
echo; bold "3) Listening sockets"
if have ss; then ss -ltnp 2>/dev/null || true; else info "ss not available."; fi
if have lsof; then
  echo; bold "3a) lsof TCP listeners"
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || /:3000|:5000|:8080|open-webui|uvicorn|python/'
else
  info "lsof not available."
fi

# ---- 4) Containers
echo; bold "4) Containers (Docker/Podman)"
FOUND_CONT=0
have docker && { docker ps --format '{{.ID}} {{.Image}} {{.Names}} {{.Status}}' | egrep -i 'open-webui' && FOUND_CONT=1 || true; }
have podman && { podman ps --format '{{.ID}} {{.Image}} {{.Names}} {{.Status}}' | egrep -i 'open-webui' && FOUND_CONT=1 || true; }
(( FOUND_CONT==0 )) && info "No open-webui containers found."

# ---- 5) Env, DATA_DIR & DB
echo; bold "5) Environment, DATA_DIR & DB"
if [[ -n "$PRIMARY_PID" ]]; then
  ok "Primary PID: $PRIMARY_PID"; dim "CMD: $PRIMARY_CMD"
  echo "Selected environment:"
  if [[ -r "/proc/$PRIMARY_PID/environ" ]]; then
    tr '\0' '\n' < "/proc/$PRIMARY_PID/environ" \
      | egrep '^(DATA_DIR|DATABASE_URL|ENABLE_PERSISTENT_CONFIG|WEBUI_URL|PORT|OLLAMA_API_BASE|OPENAI_API_BASE)=' \
      | sed 's/^/    /' || true
  else
    warn "Cannot read /proc/$PRIMARY_PID/environ (need sudo?)."
  fi
  CWD="$(readlink -f "/proc/$PRIMARY_PID/cwd" 2>/dev/null || true)"
  [[ -n "$CWD" ]] && info "Process CWD: $CWD"

  DATADIR="$(resolve_datadir "$PRIMARY_PID" "$PRIMARY_UNIT" "$CWD")"
  if [[ -n "$DATADIR" ]]; then
    ok "Resolved DATA_DIR: $DATADIR"
    [[ -d "$DATADIR/uploads" ]]   && info "uploads/: $DATADIR/uploads"
    [[ -d "$DATADIR/vector_db" ]] && info "vector_db/: $DATADIR/vector_db"
  else
    warn "DATA_DIR not set; default is ./data under working directory."
  fi

  # DB detection
  DBURL="$(tr '\0' '\n' < "/proc/$PRIMARY_PID/environ" 2>/dev/null | awk -F= '/^DATABASE_URL=/{print $2; exit}')"
  if [[ -n "$DBURL" ]]; then
    info "DATABASE_URL: $DBURL"
    if [[ "$DBURL" =~ ^sqlite ]]; then
      DBFILE="$(sed -n 's#^sqlite\+:\?//\(/\{0,1\}.*\)#\1#p' <<<"$DBURL" | head -n1)"
      [[ -n "$DBFILE" ]] && report_db_file "$DBFILE" || warn "Could not parse sqlite file from DATABASE_URL"
    else
      ok "External DB detected (non-sqlite)."
    fi
  else
    # NEW: even if DATA_DIR is unknown, try the documented default CWD/data/webui.db
    if [[ -n "$DATADIR" ]]; then
      report_db_file "$DATADIR/webui.db"
    elif [[ -n "$CWD" ]]; then
      report_db_file "$CWD/data/webui.db"
    else
      warn "No DATABASE_URL and cannot infer DB path."
    fi
  fi
else
  warn "No running Open WebUI process found to read env/paths."
fi

# ---- 6) Port check
echo; bold "6) Port check"
DERIVED_PORT="$UNIT_PORT"
[[ -z "$DERIVED_PORT" && -n "$PRIMARY_CMD" ]] && DERIVED_PORT="$(extract_port_from_cmd "$PRIMARY_CMD")"
[[ -z "$DERIVED_PORT" ]] && DERIVED_PORT="5000"
info "Derived/OpenWebUI port: ${DERIVED_PORT}"
if have curl; then
  info "HTTP probe (localhost:${DERIVED_PORT})"
  curl -sS -m 3 "http://127.0.0.1:${DERIVED_PORT}/_app/version.json" | head -c 300 || true
  echo
fi

# ---- 7) Nginx / reverse proxy scan
echo; bold "7) Nginx / reverse proxy scan"
if [[ -d /etc/nginx ]]; then
  grep -RInE 'listen\s+[0-9]+|proxy_pass\s+http' /etc/nginx 2>/dev/null | sed 's/^/  /' || true
  ACTIVE_TARGETS="$(grep -RInE 'proxy_pass\s+http' /etc/nginx/sites-enabled 2>/dev/null || true)"
  if [[ -n "$ACTIVE_TARGETS" ]]; then
    echo; bold "Active proxy targets:"; echo "$ACTIVE_TARGETS" | sed 's/^/  /'
    if ! grep -q ":${DERIVED_PORT}" <<<"$ACTIVE_TARGETS"; then
      warn "nginx proxy_pass does NOT reference port ${DERIVED_PORT}."
    else
      ok "nginx proxy_pass references the running port ${DERIVED_PORT}."
    fi
  else
    info "No active proxy_pass found in sites-enabled."
  fi
else
  info "nginx not installed or no site configs present."
fi

# ---- 8) Firewall (optional)
echo; bold "8) Firewall"
if have ufw; then ufw status verbose 2>/dev/null | sed 's/^/  /' || true; else info "ufw not installed."; fi

# ---- Summary
hr; bold "Summary"
[[ -n "$PRIMARY_UNIT" ]] && ok "Launch method: systemd unit '$PRIMARY_UNIT'"
[[ -n "$PRIMARY_PID"  ]] && ok "PID: $PRIMARY_PID"
if [[ -n "$DATADIR" ]]; then ok "DATA_DIR: $DATADIR"; else warn "DATA_DIR not set (default is ./data)"; fi
ok "Open WebUI port: $DERIVED_PORT"
hr
bold "Hints"
echo "  - Set DATA_DIR to a stable path (e.g., /var/lib/open-webui) so DB/files persist across upgrades."
echo "  - Default SQLite path is data/webui.db under your root/working dir."
echo "  - If serving via subpath, set WEBUI_URL so generated URLs match the proxy."
