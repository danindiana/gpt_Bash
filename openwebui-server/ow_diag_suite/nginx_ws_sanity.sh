#!/usr/bin/env bash
# nginx_ws_sanity.sh - sanity-check (and optionally fix) WebSocket upgrade headers for Socket.IO locations
# Usage: bash nginx_ws_sanity.sh [NGINX_DIR]
# Default NGINX_DIR=/etc/nginx

set -euo pipefail

NGINX_DIR="${1:-/etc/nginx}"
[ -d "$NGINX_DIR" ] || { echo "[FAIL] Nginx directory not found: $NGINX_DIR"; exit 2; }

# Colors
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  C_PASS="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_FAIL="$(tput setaf 1)"; C_OFF="$(tput sgr0)"
else
  C_PASS=""; C_WARN=""; C_FAIL=""; C_OFF=""
fi
pass(){ echo -e "${C_PASS}[PASS]${C_OFF} $*"; }
warn(){ echo -e "${C_WARN}[WARN]${C_OFF} $*"; }
fail(){ echo -e "${C_FAIL}[FAIL]${C_OFF} $*"; }

echo "== Nginx WebSocket sanity check =="
echo "Scanning: $NGINX_DIR"
echo

# Mode prompt
read -r -p "Choose mode: [A] Analysis (no changes)  [F] Fix (edit configs)  > " MODE
MODE="${MODE:-A}"; MODE="${MODE^^}"
case "$MODE" in
  A) DO_FIX=0; echo "Mode: Analysis (dry-run)";;
  F) DO_FIX=1; echo "Mode: Fix (will modify files with backups)";;
  *) echo "Unrecognized mode '$MODE' — defaulting to Analysis."; DO_FIX=0;;
esac
echo

# nginx -t quick test
if command -v nginx >/dev/null 2>&1; then
  if nginx -t -c "$NGINX_DIR/nginx.conf" >/dev/null 2>&1; then
    pass "nginx -t passed"
  else
    warn "nginx -t failed or has warnings (continuing)."
    nginx -t -c "$NGINX_DIR/nginx.conf" 2>&1 | sed 's/^/  │ /'
  fi
else
  warn "nginx binary not found; skipping nginx -t."
fi
echo

# Discover if a global map exists
MAP_FOUND=$(grep -RIE --line-number --no-messages \
  -e '^\s*map\s+\$http_upgrade\s+\$connection_upgrade' "$NGINX_DIR" | head -n1 || true)
if [ -n "$MAP_FOUND" ]; then
  pass "Found map for \$connection_upgrade: $MAP_FOUND"
  MAP_OK=1
else
  warn "No 'map \$http_upgrade \$connection_upgrade' found (not required if using literal Connection \"upgrade\")."
  MAP_OK=0
fi
echo

# Collect candidate files
FILES=$(find "$NGINX_DIR" -type f \( -name "*.conf" -o -path "*/sites-enabled/*" -o -path "*/conf.d/*" \) 2>/dev/null || true)
[ -n "$FILES" ] || { fail "No config files found under $NGINX_DIR"; exit 2; }

TMP_CAPTURE="$(mktemp)"; trap 'rm -f "$TMP_CAPTURE"' EXIT

# Extract all location blocks that reference socket.io
for f in $FILES; do
  awk -v file="$f" '
    BEGIN { inblock=0; depth=0 }
    {
      raw=$0
      if (inblock==0 && match(raw, /location[^{;]*socket\.io[^{;]*\{/)) {
        inblock=1; depth=0; block=""; header="===FILE:" file "==="
        print header
      }
      if (inblock==1) {
        block = block raw "\n"
        # naive brace count
        gsub(/[^\{\}]/, "", raw)
        for (i=1;i<=length(raw);i++) {
          c=substr(raw,i,1)
          if (c=="{") depth++
          if (c=="}") depth--
        }
        if (depth==0) {
          printf "%s", block
          inblock=0; block=""
        }
      }
    }
  ' "$f" >> "$TMP_CAPTURE"
done

if ! grep -q '^===FILE:' "$TMP_CAPTURE"; then
  fail "No 'location ... socket.io { ... }' blocks found."
  echo "Example to add (edit upstream to match your setup):"
  cat <<'NGX'
  location /ws/socket.io/ {
      proxy_pass http://openwebui_upstream;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade"; # or $connection_upgrade with a map
  }
NGX
  exit 2
fi

# Analysis pass over captured blocks
ANY_LOC=0; OK_LOC=0; BAD_LOC=0; NEED_CONN_VAR=0
declare -A FILE_BLOCKS_PRESENT

echo "== Analyzing Socket.IO locations =="
echo

CURRENT_FILE=""
CURRENT_BLOCK=""
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^===FILE: ]]; then
    # flush previous
    if [ -n "$CURRENT_BLOCK" ]; then
      ANY_LOC=$((ANY_LOC+1))
      echo "----"
      echo "File: $CURRENT_FILE"
      echo "$CURRENT_BLOCK" | sed 's/^/    │ /'
      has_pass=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_pass\s+' && echo 1 || echo 0)
      has_proxy_http=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_http_version\s+1\.1\s*;' && echo 1 || echo 0)
      has_upgrade=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Upgrade\s+\$http_upgrade\s*;' && echo 1 || echo 0)
      has_conn_var=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+\$connection_upgrade\s*;' && echo 1 || echo 0)
      has_conn_lit=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+"?upgrade"?\s*;' && echo 1 || echo 0)
      has_conn=$(( has_conn_var == 1 || has_conn_lit == 1 ? 1 : 0 ))
      [ $has_conn_var -eq 1 ] && NEED_CONN_VAR=1
      if [ $has_pass -eq 1 ] && [ $has_proxy_http -eq 1 ] && [ $has_upgrade -eq 1 ] && [ $has_conn -eq 1 ]; then
        pass "Directives complete."
        OK_LOC=$((OK_LOC+1))
      else
        fail "Missing directives in this location:"
        [ $has_pass -eq 1 ]       || echo "  - proxy_pass (required)"
        [ $has_proxy_http -eq 1 ] || echo "  - proxy_http_version 1.1; (required)"
        [ $has_upgrade -eq 1 ]    || echo '  - proxy_set_header Upgrade $http_upgrade; (required)'
        if [ $has_conn -eq 0 ]; then
          echo '  - proxy_set_header Connection "upgrade";  OR  proxy_set_header Connection $connection_upgrade; (required)'
        fi
        BAD_LOC=$((BAD_LOC+1))
      fi
      FILE_BLOCKS_PRESENT["$CURRENT_FILE"]=1
      CURRENT_BLOCK=""
    fi
    CURRENT_FILE="${line#===FILE:}"; CURRENT_FILE="${CURRENT_FILE%===}"
    continue
  fi
  CURRENT_BLOCK+="$line"$'\n'
done < "$TMP_CAPTURE"

# flush last
if [ -n "$CURRENT_BLOCK" ]; then
  ANY_LOC=$((ANY_LOC+1))
  echo "----"
  echo "File: $CURRENT_FILE"
  echo "$CURRENT_BLOCK" | sed 's/^/    │ /'
  has_pass=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_pass\s+' && echo 1 || echo 0)
  has_proxy_http=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_http_version\s+1\.1\s*;' && echo 1 || echo 0)
  has_upgrade=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Upgrade\s+\$http_upgrade\s*;' && echo 1 || echo 0)
  has_conn_var=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+\$connection_upgrade\s*;' && echo 1 || echo 0)
  has_conn_lit=$(echo "$CURRENT_BLOCK" | grep -Eiq '^\s*proxy_set_header\s+Connection\s+"?upgrade"?\s*;' && echo 1 || echo 0)
  has_conn=$(( has_conn_var == 1 || has_conn_lit == 1 ? 1 : 0 ))
  [ $has_conn_var -eq 1 ] && NEED_CONN_VAR=1
  if [ $has_pass -eq 1 ] && [ $has_proxy_http -eq 1 ] && [ $has_upgrade -eq 1 ] && [ $has_conn -eq 1 ]; then
    pass "Directives complete."
    OK_LOC=$((OK_LOC+1))
  else
    fail "Missing directives in this location:"
    [ $has_pass -eq 1 ]       || echo "  - proxy_pass (required)"
    [ $has_proxy_http -eq 1 ] || echo "  - proxy_http_version 1.1; (required)"
    [ $has_upgrade -eq 1 ]    || echo '  - proxy_set_header Upgrade $http_upgrade; (required)'
    if [ $has_conn -eq 0 ]; then
      echo '  - proxy_set_header Connection "upgrade";  OR  proxy_set_header Connection $connection_upgrade; (required)'
    fi
    BAD_LOC=$((BAD_LOC+1))
  fi
  FILE_BLOCKS_PRESENT["$CURRENT_FILE"]=1
fi

echo
echo "== Summary =="
echo "Locations found: $ANY_LOC"
echo "Locations OK:    $OK_LOC"
echo "Locations bad:   $BAD_LOC"
[ $NEED_CONN_VAR -eq 1 ] && [ $MAP_OK -eq 0 ] && warn "Some blocks use \$connection_upgrade but no global map exists."

# Exit early in Analysis mode
if [ "$DO_FIX" -eq 0 ]; then
  echo
  echo "Dry-run complete. No files modified."
  exit $([ $BAD_LOC -gt 0 ] && echo 1 || echo 0)
fi

# Confirm before Fix
echo
read -r -p "Proceed with automatic fixes? This will modify files (backups created). [y/N] " CONFIRM
case "${CONFIRM:-N}" in
  y|Y) ;;
  *) echo "Aborted by user."; exit 1;;
fi

# Decide whether we will add a map file if needed
ADD_MAP=0
if [ $MAP_OK -eq 0 ] && [ $NEED_CONN_VAR -eq 1 ]; then
  # Prefer adding a map file if conf.d includes are active
  if grep -Eq 'include\s+/etc/nginx/conf\.d/\*\.conf;' "$NGINX_DIR/nginx.conf"; then
    ADD_MAP=1
  else
    warn "nginx.conf does not include /etc/nginx/conf.d/*.conf; cannot auto-add map. Will switch to literal Connection \"upgrade\" fixes."
  fi
fi

# Fix pass: for each file with socket.io location blocks, patch them
TS="$(date +%Y%m%d-%H%M%S)"
FIXED_FILES=0
for f in "${!FILE_BLOCKS_PRESENT[@]}"; do
  # Create backup
  cp -a "$f" "$f.bak.$TS"

  # Run AWK fixer
  awk -v add_map="$ADD_MAP" -v map_ok="$MAP_OK" '
    function has(line, re) { return (line ~ re) }
    function print_block_and_fix(buf,    i,need_proxy_http,need_upgrade,need_conn_lit,need_conn_var,indent,seen_indent) {
      # Determine what exists
      need_proxy_http=1; need_upgrade=1; need_conn_lit=1; need_conn_var=1
      for (i=1;i<=length(buf);i++) {
        if (buf[i] ~ /^[[:space:]]*proxy_http_version[[:space:]]+1\.1[[:space:]]*;/) need_proxy_http=0
        if (buf[i] ~ /^[[:space:]]*proxy_set_header[[:space:]]+Upgrade[[:space:]]+\$http_upgrade[[:space:]]*;/) need_upgrade=0
        if (buf[i] ~ /^[[:space:]]*proxy_set_header[[:space:]]+Connection[[:space:]]+"?upgrade"?[[:space:]]*;/) need_conn_lit=0
        if (buf[i] ~ /^[[:space:]]*proxy_set_header[[:space:]]+Connection[[:space:]]+\$connection_upgrade[[:space:]]*;/) need_conn_var=0
      }
      # Choose connection strategy:
      # - if map exists or will be added, prefer $connection_upgrade
      # - else use literal "upgrade"
      use_var=(map_ok==1 || add_map==1) ? 1 : 0

      # Find indentation (first inner line)
      indent="    "; seen_indent=0
      for (i=1;i<=length(buf);i++) {
        if (buf[i] ~ /\{[[:space:]]*$/) { # opening line; next lines determine indent
          continue
        }
        if (!seen_indent && buf[i] ~ /^[[:space:]]*[^[:space:]}]/) {
          match(buf[i], /^[[:space:]]*/)
          indent=substr(buf[i], RSTART, RLENGTH)
          seen_indent=1
        }
      }

      # Print block up to the closing brace, then add missing lines before the brace
      for (i=1;i<=length(buf);i++) {
        if (buf[i] ~ /^[[:space:]]*}[[:space:]]*$/) {
          if (need_proxy_http) print indent "proxy_http_version 1.1;"
          if (need_upgrade)    print indent "proxy_set_header Upgrade $http_upgrade;"
          if (need_conn_lit && need_conn_var) {
            if (use_var) print indent "proxy_set_header Connection $connection_upgrade;"
            else         print indent "proxy_set_header Connection \"upgrade\";"
          }
          print buf[i]
        } else {
          print buf[i]
        }
      }
    }
    BEGIN{ inblock=0; depth=0; bi=0 }
    {
      raw=$0
      if (inblock==0 && raw ~ /location[^{;]*socket\.io[^{;]*\{/) {
        inblock=1; depth=0; delete block; bi=0
      }
      if (inblock==1) {
        bi++; block[bi]=raw
        tmp=raw; gsub(/[^\{\}]/,"",tmp)
        for (i=1;i<=length(tmp);i++) {
          c=substr(tmp,i,1); if (c=="{") depth++; if (c=="}") depth--
        }
        if (depth==0) {
          print_block_and_fix(block)
          inblock=0; delete block; bi=0
        }
      } else {
        print raw
      }
    }
  ' "$f" > "$f.tmp.$TS"

  # Replace only if changed
  if ! cmp -s "$f" "$f.tmp.$TS"; then
    mv "$f.tmp.$TS" "$f"
    FIXED_FILES=$((FIXED_FILES+1))
    pass "Patched: $f"
  else
    rm -f "$f.tmp.$TS"
  fi
done

# Add map file if needed
if [ "$ADD_MAP" -eq 1 ]; then
  MAP_FILE="$NGINX_DIR/conf.d/connection_upgrade.map.conf"
  if [ -e "$MAP_FILE" ]; then
    warn "Map file already exists: $MAP_FILE"
  else
    cat > "$MAP_FILE" <<'MAP'
# Auto-added by nginx_ws_sanity.sh
map $http_upgrade $connection_upgrade {
    default   close;
    upgrade   upgrade;
}
MAP
    pass "Added map file: $MAP_FILE"
  fi
fi

echo
if command -v nginx >/dev/null 2>&1; then
  if nginx -t -c "$NGINX_DIR/nginx.conf"; then
    pass "nginx -t after fixes: OK"
    if command -v systemctl >/dev/null 2>&1; then
      read -r -p "Reload Nginx now? [y/N] " R
      case "${R:-N}" in
        y|Y) systemctl reload nginx && pass "Nginx reloaded." || warn "Reload failed; check permissions."; ;;
        *) echo "Skipping reload."; ;;
      esac
    else
      echo "You can reload Nginx with: nginx -s reload"
    fi
  else
    fail "nginx -t failed after changes. Backups with .bak.$TS are available."
    exit 1
  fi
else
  warn "nginx not found; cannot validate or reload."
fi

echo
echo "Fix mode complete. Files changed: $FIXED_FILES"
exit 0
