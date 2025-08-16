#!/usr/bin/env bash
# Open WebUI launcher & config probe (v3.2)
# Adds: DB hunt via lsof + /proc/$pid/fd, and --fix-datadir action.

set -euo pipefail

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
dim(){ printf "\033[2m%s\033[0m\n" "$*"; }
info(){ printf "  - %s\n" "$*"; }
warn(){ printf "\033[33m⚠ %s\033[0m\n" "$*"; }
ok(){ printf "\033[32m✓ %s\033[0m\n" "$*"; }
hr(){ printf "%s\n" "------------------------------------------------------------"; }
have(){ command -v "$1" >/dev/null 2>&1; }

FIX_DATADIR=""

while (( "$#" )); do
  case "${1:-}" in
    --fix-datadir)
      shift; FIX_DATADIR="${1:-}"; shift || true
      ;;
    *)
      warn "Unknown arg: $1"; shift;;
  esac
done

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
      size=$(stat -c '%s' "$path"); mtime=$(date -d "@$(stat -c '%Y' "$path")")
    else
      size=$(stat -f '%z' "$path"); mtime=$(stat -f '%Sm' "$path")
    fi
    ok "SQLite DB: $path"
    info "Size: ${size} bytes"
    info "Modified: $mtime"
  else
    warn "No SQLite DB at: $path"
  fi
}

hunt_db_paths(){
  local pid="$1" cwd="$2" datadir_guess="$3"
  local found=0
  bold "5a) DB hunt (open files)"
  if have lsof; then
    lsof -nP -p "$pid" 2>/dev/null | awk '/webui\.db|\.sqlite/ {print "  " $0; f=1} END{if(!f) print "  (no matching open sqlite files)"}'
    if lsof -nP -p "$pid" 2>/dev/null | grep -q 'webui\.db'; then found=1; fi
  else
    info "lsof not available."
  fi
  bold "5b) DB hunt (/proc/$pid/fd symlinks)"
  local hit=0
  for fd in /proc/"$pid"/fd/*; do
    [[ -L "$fd" ]] || continue
    local tgt; tgt="$(readlink -f "$fd" 2>/dev/null || true)"
    if [[ "$tgt" =~ webui\.db ]]; then
      echo "  $fd -> $tgt"; hit=1; found=1
    fi
  done
  (( hit==0 )) && info "(no fd symlinks to webui.db)"
  # Also check likely defaults:
  [[ -n "$datadir_guess" ]] && report_db_file "$datadir_guess/webui.db"
  [[ -n "$cwd" ]] && [[ "$datadir_guess" != "$cwd/data" ]] && report_db_file "$cwd/data/webui.db"
  return $found
}

do_fix_datadir(){
  local unit="$1" user="$2" src_cwd="$3" datadir_new="$4"
  [[ -z "$datadir_new" ]] && { warn "Missing --fix-datadir PATH"; return 1; }
  bold "FIX: setting DATA_DIR -> $datadir_new"
  sudo mkdir -p "$datadir_new"
  sudo chown "$user":"$user" "$datadir_new"
  # Try to move any existing data folders if present:
  local moved=0
  for d in "$src_cwd/data" "$HOME/.open-webui" ; do
    if [[ -d "$d" && "$d" != "$datadir_new" ]]; then
      echo "  moving existing $d/* -> $datadir_new/"
      rsync -a --ignore-missing-args "$d"/ "$datadir_new"/ || true
      moved=1
    fi
  done
  # Write/replace drop-in
  sudo mkdir -p "/etc/systemd/system/$unit.d"
  cat <<EOF | sudo tee "/etc/systemd/system/$unit.d/10-datadir.conf" >/dev/null
[Service]
Environment=DATA_DIR=$datadir_new
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart "$unit"
  ok "Restarted $unit with DATA_DIR=$datadir_new"
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
UNIT_WD="$(systemctl show -p WorkingDirectory --value "$PRIMARY_UNIT" 2>/dev/null || true)"
UNIT_EXEC="$(systemctl show -p ExecStart --value "$PRIMARY_UNIT" 2>/dev/null || true)"
UNIT_PORT="$(extract_port_from_cmd "$UNIT_EXEC")"

# ---- 3) Listening sockets
echo; bold "3) Listening sockets"
if have ss; then ss -ltnp 2>/dev/null || true; else info "ss not available."; fi
if have lsof; then
  echo; bold "3a) lsof TCP listeners"
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || /:3000|:5000|:8080|open-webui|uvicorn|python/'
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
      | egrep '^(DATA_DIR|DATABASE_URL|ENABLE_PERSISTENT_CONFIG|WEBUI_URL|PORT|WEBUI_SECRET_KEY)=' \
      | sed 's/^/    /' || true
  fi
  CWD="$(readlink -f "/proc/$PRIMARY_PID/cwd" 2>/dev/null || true)"
  [[ -n "$CWD" ]] && info "Process CWD: $CWD"
  DATADIR="$(resolve_datadir "$PRIMARY_PID" "$PRIMARY_UNIT" "$CWD")"
  if [[ -n "$DATADIR" ]]; then ok "Resolved DATA_DIR: $DATADIR"; else warn "DATA_DIR not set; default is ./data under working directory."; fi
  DBURL="$(tr '\0' '\n' < "/proc/$PRIMARY_PID/environ" 2>/dev/null | awk -F= '/^DATABASE_URL=/{print $2; exit}')"
  if [[ -n "$DBURL" ]]; then info "DATABASE_URL: $DBURL"; fi
  echo
  hunt_db_paths "$PRIMARY_PID" "$CWD" "$DATADIR" || true
else
  warn "No running Open WebUI process found to read env/paths."
fi

# ---- 6) Port check
echo; bold "6) Port check"
DERIVED_PORT="${UNIT_PORT:-}"
[[ -z "$DERIVED_PORT" && -n "$PRIMARY_CMD" ]] && DERIVED_PORT="$(extract_port_from_cmd "$PRIMARY_CMD")"
[[ -z "$DERIVED_PORT" ]] && DERIVED_PORT="5000"
info "Derived/OpenWebUI port: ${DERIVED_PORT}"
have curl && { info "HTTP probe (localhost:${DERIVED_PORT})"; curl -sS -m 3 "http://127.0.0.1:${DERIVED_PORT}/_app/version.json" | head -c 300; echo; }

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

# ---- 8) Firewall
echo; bold "8) Firewall"
have ufw && ufw status verbose 2>/dev/null | sed 's/^/  /' || info "ufw not installed."

# ---- Optional fix
if [[ -n "$FIX_DATADIR" && -n "$PRIMARY_UNIT" && -n "$CWD" ]]; then
  do_fix_datadir "$PRIMARY_UNIT" "$(id -un)" "$CWD" "$FIX_DATADIR"
fi

# ---- Summary
hr; bold "Summary"
[[ -n "$PRIMARY_UNIT" ]] && ok "Launch method: systemd unit '$PRIMARY_UNIT'"
[[ -n "$PRIMARY_PID"  ]] && ok "PID: $PRIMARY_PID"
[[ -n "$DATADIR" ]] && ok "DATA_DIR: $DATADIR" || warn "DATA_DIR not set (default is ./data)"
ok "Open WebUI port: $DERIVED_PORT"
hr
bold "Hints"
echo "  - Default DB URL: sqlite://\${DATA_DIR}/webui.db (set DATA_DIR to pin your storage)."
echo "  - Consider WEBUI_SECRET_KEY to keep sessions stable across updates."
echo "  - If serving behind subpath/domain, set WEBUI_URL accordingly."
