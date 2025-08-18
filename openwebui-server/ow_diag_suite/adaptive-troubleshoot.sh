#!/usr/bin/env bash
# adaptive-troubleshoot.sh
# Prints an evidence ledger and suggested next probe for:
#   - WebSocket/Nginx (Socket.IO upgrades)
#   - npm/CLI (gemini-cli command discovery)
# No system changes are made. Pure analysis.

set -euo pipefail

# ---------- UI helpers ----------
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  C_H="$(tput bold)"; C_OFF="$(tput sgr0)"
  C_PASS="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_FAIL="$(tput setaf 1)"
else
  C_H=""; C_OFF=""; C_PASS=""; C_WARN=""; C_FAIL=""
fi
say() { echo -e "$*"; }
pass(){ say "${C_PASS}[PASS]${C_OFF} $*"; }
warn(){ say "${C_WARN}[WARN]${C_OFF} $*"; }
fail(){ say "${C_FAIL}[FAIL]${C_OFF} $*"; }
hr(){ printf '%*s\n' "${1:-70}" '' | tr ' ' '-'; }

usage() {
  cat <<USAGE
Usage: $0 [--case nginx|npm] [--nginx-dir /etc/nginx] [--host example.com]

Options:
  --case nginx       Run the WebSocket/Nginx analyzer
  --case npm         Run the npm/CLI analyzer (gemini-cli)
  --nginx-dir PATH   Nginx root directory (default: /etc/nginx)
  --host HOSTNAME    Optional HTTPS host to probe for /socket.io and /ws/socket.io (curl -I)
  -h, --help         Show this help

By default, runs an interactive menu to choose the case.
No changes are made to your system; this is analysis-only.
USAGE
}

# ---------- args ----------
CASE=""
NGINX_DIR="/etc/nginx"
HOST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --case) CASE="${2:-}"; shift 2;;
    --nginx-dir) NGINX_DIR="${2:-}"; shift 2;;
    --host) HOST="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) warn "Unknown arg: $1"; shift;;
  esac
done

# ---------- Evidence Ledger helpers ----------
start_ledger() {
  hr
  say "${C_H}Evidence Ledger${C_OFF}"
  hr
}
entry() {
  local k="$1"; shift
  say "${C_H}${k}:${C_OFF} $*"
}
bullet() { echo "  - $*"; }
next_probe() {
  hr
  say "${C_H}Suggested Next Probe${C_OFF}"
  hr
  echo "$@"
}
success_criteria() {
  hr
  say "${C_H}Success Criteria${C_OFF}"
  hr
  echo "$@"
}

# ---------- Module: WebSocket/Nginx ----------
analyze_nginx() {
  say "${C_H}Case: WebSocket/Nginx (Socket.IO)${C_OFF}"
  echo "Nginx dir: $NGINX_DIR"
  [ -d "$NGINX_DIR" ] || { fail "Nginx directory not found: $NGINX_DIR"; exit 2; }

  # quick syntax test
  if command -v nginx >/dev/null 2>&1; then
    if nginx -t -c "$NGINX_DIR/nginx.conf" >/dev/null 2>&1; then
      pass "nginx -t OK"
    else
      warn "nginx -t reported issues (see below). Continuing."
      nginx -t -c "$NGINX_DIR/nginx.conf" 2>&1 | sed 's/^/  │ /'
    fi
  else
    warn "nginx binary not found; skipping syntax test."
  fi

  # detect map
  local MAP_FOUND
  MAP_FOUND=$(grep -RIE --line-number --no-messages \
    -e '^\s*map\s+\$http_upgrade\s+\$connection_upgrade' "$NGINX_DIR" | head -n1 || true)

  # capture socket.io locations and evaluate directives
  local TMP_CAPTURE; TMP_CAPTURE="$(mktemp)"; trap 'rm -f "$TMP_CAPTURE"' EXIT
  local FILES; FILES=$(find "$NGINX_DIR" -type f \( -name "*.conf" -o -path "*/sites-enabled/*" -o -path "*/conf.d/*" \) 2>/dev/null || true)
  if [ -z "$FILES" ]; then
    fail "No Nginx config files found."
    exit 2
  fi

  for f in $FILES; do
    awk -v file="$f" '
      BEGIN { inb=0; depth=0 }
      {
        raw=$0
        if (inb==0 && match(raw, /location[^{;]*socket\.io[^{;]*\{/)) {
          inb=1; depth=0; printf "===FILE:%s===\n", file
        }
        if (inb==1) {
          print raw
          tmp=raw; gsub(/[^\{\}]/,"",tmp)
          for (i=1;i<=length(tmp);i++){ c=substr(tmp,i,1); if(c=="{")depth++; if(c=="}")depth-- }
          if (depth==0) inb=0
        }
      }
    ' "$f" >> "$TMP_CAPTURE"
  done

  # logs: skim for socket.io evidence
  local A_LOG E_LOG
  A_LOG=$( (tail -n 300 /var/log/nginx/access.log /var/log/nginx/access.log.* 2>/dev/null || true) | egrep -i 'socket\.io' | tail -n 30 || true)
  E_LOG=$( (tail -n 200 /var/log/nginx/error.log /var/log/nginx/error.log.* 2>/dev/null || true) | egrep -i 'websocket|upgrade|socket\.io|engine\.io' | tail -n 30 || true)

  # config evaluation
  local ANY=0 OK=0 BAD=0 NEED_VAR=0
  local CURRENT_FILE=""; local CURRENT_BLOCK=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^===FILE: ]]; then
      if [ -n "$CURRENT_BLOCK" ]; then
        ANY=$((ANY+1))
        # checks:
        local has_pass has_http has_up has_conn_var has_conn_lit has_conn
        echo "-----"
        echo "File: $CURRENT_FILE"
        echo "$CURRENT_BLOCK" | sed 's/^/    │ /'
        has_pass=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_pass\s+' && echo 1 || echo 0)
        has_http=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_http_version\s+1\.1\s*;' && echo 1 || echo 0)
        has_up=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Upgrade\s+\$http_upgrade\s*;' && echo 1 || echo 0)
        has_conn_var=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+\$connection_upgrade\s*;' && echo 1 || echo 0)
        has_conn_lit=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+"?upgrade"?\s*;' && echo 1 || echo 0)
        has_conn=$(( has_conn_var==1 || has_conn_lit==1 ? 1 : 0 ))
        [ $has_conn_var -eq 1 ] && NEED_VAR=1
        if [ $has_pass -eq 1 ] && [ $has_http -eq 1 ] && [ $has_up -eq 1 ] && [ $has_conn -eq 1 ]; then
          pass "Location has required upgrade directives."
          OK=$((OK+1))
        else
          fail "Missing directives:"
          [ $has_pass -eq 1 ] || bullet "proxy_pass (required)"
          [ $has_http -eq 1 ] || bullet "proxy_http_version 1.1; (required)"
          [ $has_up -eq 1 ]   || bullet "proxy_set_header Upgrade \$http_upgrade; (required)"
          if [ $has_conn -eq 0 ]; then
            bullet 'proxy_set_header Connection "upgrade"; OR proxy_set_header Connection $connection_upgrade; (required)'
          fi
          BAD=$((BAD+1))
        fi
        CURRENT_BLOCK=""
      fi
      CURRENT_FILE="${line#===FILE:}"; CURRENT_FILE="${CURRENT_FILE%===}"
      continue
    fi
    CURRENT_BLOCK+="$line"$'\n'
  done < "$TMP_CAPTURE"

  if [ -n "$CURRENT_BLOCK" ]; then
    ANY=$((ANY+1))
    echo "-----"
    echo "File: $CURRENT_FILE"
    echo "$CURRENT_BLOCK" | sed 's/^/    │ /'
    local has_pass has_http has_up has_conn_var has_conn_lit has_conn
    has_pass=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_pass\s+' && echo 1 || echo 0)
    has_http=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_http_version\s+1\.1\s*;' && echo 1 || echo 0)
    has_up=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Upgrade\s+\$http_upgrade\s*;' && echo 1 || echo 0)
    has_conn_var=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+\$connection_upgrade\s*;' && echo 1 || echo 0)
    has_conn_lit=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+"?upgrade"?\s*;' && echo 1 || echo 0)
    has_conn=$(( has_conn_var==1 || has_conn_lit==1 ? 1 : 0 ))
    [ $has_conn_var -eq 1 ] && NEED_VAR=1
    if [ $has_pass -eq 1 ] && [ $has_http -eq 1 ] && [ $has_up -eq 1 ] && [ $has_conn -eq 1 ]; then
      pass "Location has required upgrade directives."
      OK=$((OK+1))
    else
      fail "Missing directives:"
      [ $has_pass -eq 1 ] || bullet "proxy_pass (required)"
      [ $has_http -eq 1 ] || bullet "proxy_http_version 1.1; (required)"
      [ $has_up -eq 1 ]   || bullet "proxy_set_header Upgrade \$http_upgrade; (required)"
      if [ $has_conn -eq 0 ]; then
        bullet 'proxy_set_header Connection "upgrade"; OR proxy_set_header Connection $connection_upgrade; (required)'
      fi
      BAD=$((BAD+1))
    fi
  fi

  # Evidence ledger
  start_ledger
  entry "Symptom" "Realtime chat feels laggy or falls back to polling; curl tests confusing; intermittent 400s."
  entry "Observations"
  [ -n "$MAP_FOUND" ] && bullet "Global map for \$connection_upgrade exists: $MAP_FOUND" || bullet "No global map found for \$connection_upgrade"
  bullet "Socket.IO locations found: $ANY (OK=$OK, Bad=$BAD)"
  if [ -n "$A_LOG" ]; then
    bullet "Access log tail with socket.io (last 30):"
    echo "$A_LOG" | sed 's/^/    │ /'
  else
    bullet "Access log socket.io lines: none readable or none present"
  fi
  if [ -n "$E_LOG" ]; then
    bullet "Error log tail (upgrade/websocket keywords):"
    echo "$E_LOG" | sed 's/^/    │ /'
  fi
  entry "Current Hypothesis" "If any socket.io locations lack upgrade headers or correct path, Engine.IO stays in polling mode."

  # Optional host curl probes
  if [ -n "$HOST" ]; then
    echo
    say "${C_H}Live host probes (HEAD)${C_OFF}"
    hr
    for p in "/socket.io/?EIO=4&transport=polling" "/ws/socket.io/?EIO=4&transport=polling"; do
      echo "curl -I https://$HOST$p"
      curl -I -sS "https://$HOST$p" | sed 's/^/  /' || true
      echo
    done
    bullet "Note: 400 responses can be normal if handshake not performed; we are checking reachability and proxying."
  fi

  # Next probe / success criteria
  local probe=""
  if [ "$BAD" -gt 0 ]; then
    probe=$(cat <<'P'
1) Show offending blocks with line numbers:
   grep -RInE 'location[^{;]*/(ws/)?socket\.io/?' /etc/nginx

2) For each bad block, add inside the { }:
   proxy_http_version 1.1;
   proxy_set_header Upgrade $http_upgrade;
   proxy_set_header Connection "upgrade";   # or: Connection $connection_upgrade; if a map is present

3) Test and reload:
   sudo nginx -t && sudo systemctl reload nginx
P
)
  else
    probe=$(cat <<'P'
1) Verify live WebSocket upgrades in browser DevTools (Network → WS)
2) Confirm stable 101 Switching Protocols on the upgraded request.
3) If still seeing fallback, grep logs for Engine.IO params and ensure the client path matches your location (e.g., /ws/socket.io/).
P
)
  fi

  next_probe "$probe"
  success_criteria "$(cat <<'S'
- Nginx config test passes: nginx -t
- At least one location /socket.io/ or /ws/socket.io/ contains all four directives
- Browser shows WebSocket upgrade (101) and messages stream without multi-second polling delays
S
)"
}

# ---------- Module: npm/CLI (gemini-cli) ----------
analyze_npm() {
  say "${C_H}Case: npm/CLI (gemini-cli command)${C_OFF}"

  # version triplet
  local NODEV NPMV
  NODEV=$( (node -v 2>/dev/null) || echo "not found")
  NPMV=$( (npm -v 2>/dev/null) || echo "not found")
  [ "$NODEV" != "not found" ] && pass "node $NODEV" || warn "node not found"
  [ "$NPMV" != "not found" ] && pass "npm $NPMV" || warn "npm not found"

  # npx check (ad-hoc)
  local NPX_VER
  NPX_VER=$( (npx -y @google/gemini-cli@latest --version 2>/dev/null) || true )
  if [ -n "$NPX_VER" ]; then pass "npx gemini-cli: $NPX_VER"; else warn "npx gemini-cli failed (network or npm missing)"; fi

  # prefix and bin
  local PREFIX BIN GEM_SHIM PATH_HAS_BIN INSTALLED_G
  PREFIX=$( (npm config get prefix 2>/dev/null) || echo "" )
  BIN=""
  [ -n "$PREFIX" ] && BIN="$PREFIX/bin"
  if [ -n "$BIN" ] && [ -d "$BIN" ]; then
    pass "npm prefix: $PREFIX"
  else
    warn "Could not determine npm global prefix; nvm or environment may be nonstandard."
  fi

  # shim?
  local SHIM_PATH=""
  if [ -n "$BIN" ]; then
    SHIM_PATH="$BIN/gemini"
    if [ -x "$SHIM_PATH" ]; then
      pass "Found gemini shim at: $SHIM_PATH"
    else
      warn "No gemini shim at: $SHIM_PATH"
    fi
  fi

  # PATH contains BIN?
  PATH_HAS_BIN=0
  if [ -n "$BIN" ]; then
    case ":$PATH:" in
      *":$BIN:"*) PATH_HAS_BIN=1; pass "PATH includes $BIN";;
      *) warn "PATH missing $BIN";;
    esac
  fi

  # global install presence
  INSTALLED_G=$( (npm ls -g --depth=0 2>/dev/null | grep -i '@google/gemini-cli@' || true) )
  if [ -n "$INSTALLED_G" ]; then pass "Global package present: $(echo "$INSTALLED_G" | awk '{print $1}')"; else warn "Global package not found in npm ls -g"; fi

  # command -v gemini
  local WHICH
  WHICH=$( (command -v gemini 2>/dev/null) || true )
  if [ -n "$WHICH" ]; then pass "command -v gemini → $WHICH"; else warn "gemini not on PATH"; fi

  # Evidence ledger
  start_ledger
  entry "Symptom" "Running 'gemini' prints: command not found"
  entry "Observations"
  bullet "node: $NODEV, npm: $NPMV"
  bullet "npx @google/gemini-cli --version: ${NPX_VER:-unavailable}"
  bullet "npm prefix: ${PREFIX:-unknown}"
  bullet "global bin: ${BIN:-unknown}"
  bullet "gemini shim present: $([ -x "${SHIM_PATH:-/dev/null}" ] && echo yes || echo no)"
  bullet "PATH has global bin: $([ ${PATH_HAS_BIN:-0} -eq 1 ] && echo yes || echo no)"
  bullet "npm ls -g shows gemini-cli: $([ -n "$INSTALLED_G" ] && echo yes || echo no)"
  entry "Current Hypothesis" "Either global install missing, or shim exists but bin dir is not on PATH, or install landed under a different prefix (nvm/root mismatch)."

  # Next probe recommendation based on branch
  local probe=""
  if [ -n "$NPX_VER" ] && [ -z "$INSTALLED_G" ]; then
    probe=$(cat <<P
1) Install globally for the current user:
   npm i -g @google/gemini-cli@latest
2) Re-check:
   command -v gemini && gemini --version
P
)
  elif [ -n "$INSTALLED_G" ] && [ -n "$BIN" ] && [ ! -x "$SHIM_PATH" ]; then
    probe=$(cat <<P
1) Force re-link the shim and print the bin path:
   npm i -g @google/gemini-cli@latest --force && echo "Global bin: $(npm config get prefix)/bin"
2) Re-check:
   ls -l "$(npm config get prefix)/bin/gemini"
   command -v gemini
P
)
  elif [ -x "${SHIM_PATH:-/dev/null}" ] && [ ${PATH_HAS_BIN:-0} -eq 0 ]; then
    probe=$(cat <<P
1) Add global bin to PATH (bash):
   echo 'export PATH="$(npm config get prefix)/bin:\$PATH"' >> ~/.bashrc
   . ~/.bashrc
2) Re-check:
   command -v gemini && gemini --version
P
)
  else
    probe=$(cat <<'P'
1) Check for root-vs-user mismatch (no password prompt):
   sudo -n npm bin -g 2>/dev/null || echo "no sudo or not configured"
   sudo -n command -v gemini 2>/dev/null || true

2) If the command exists only for root, prefer a clean user install:
   sudo npm rm -g @google/gemini-cli || true
   npm i -g @google/gemini-cli@latest

3) If still blocked, use a zero-wait wrapper:
   mkdir -p ~/bin
   printf '#!/usr/bin/env bash\nexec npx -y @google/gemini-cli@latest "$@"\n' > ~/bin/gemini
   chmod +x ~/bin/gemini
   echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc ; . ~/.bashrc
   gemini --version
P
)
  fi

  next_probe "$probe"
  success_criteria "$(cat <<'S'
- `gemini --version` prints a version (e.g., 0.1.x)
- `command -v gemini` resolves to your user’s npm global bin (not root)
- Optional: `npx -y @google/gemini-cli@latest --version` also works as fallback
S
)"
}

# ---------- Main ----------
if [ -z "$CASE" ]; then
  echo "Choose a case:"
  echo "  1) WebSocket / Nginx (Socket.IO)"
  echo "  2) npm / CLI (gemini-cli)"
  read -r -p "> " CH
  case "$CH" in
    1) CASE="nginx";;
    2) CASE="npm";;
    *) echo "Unknown choice. Exiting."; exit 1;;
  esac
fi

case "$CASE" in
  nginx) analyze_nginx;;
  npm) analyze_npm;;
  *) echo "Unknown case: $CASE"; usage; exit 1;;
esac
