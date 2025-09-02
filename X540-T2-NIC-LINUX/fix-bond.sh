#!/usr/bin/env bash
# Bond Restore Script (v2) — resilient LACP bring-up + health checks
# Targets: bond0 with slaves enp3s0f0 and enp3s0f1
# Flags:
#   --mode {802.3ad|active-backup}   (default: 802.3ad)
#   --eee-off                        (disable EEE on slaves)
#   --retry-sec N                    (default: 60)
#   --status | --restart | --help

set -u
export LC_ALL=C

# ---------- styling ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_i(){ echo -e "${GREEN}[INFO]${NC} $*"; }
log_w(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
log_e(){ echo -e "${RED}[ERROR]${NC} $*"; }

# ---------- defaults ----------
BOND_NAME="bond0"
SLAVES=(enp3s0f0 enp3s0f1)
MODE="802.3ad"
EEE_OFF=0
RETRY_SEC=60

# ---------- argparse ----------
while (( $# )); do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2;;
    --eee-off) EEE_OFF=1; shift;;
    --retry-sec) RETRY_SEC="${2:-60}"; shift 2;;
    --status|-s) ACTION="status"; shift;;
    --restart|-r) ACTION="restart"; shift;;
    --help|-h)
      cat <<EOF
Usage: $0 [--mode 802.3ad|active-backup] [--eee-off] [--retry-sec N] [--status|--restart]
EOF
      exit 0;;
    *) log_w "Unknown option: $1"; shift;;
  esac
done
ACTION="${ACTION:-main}"

# ---------- helpers ----------
ensure_root(){ [[ $EUID -eq 0 ]] || { log_e "Run as root"; exit 1; }; }

run(){ # run <cmd...>
  if "$@"; then return 0; fi
  local rc=$?
  log_w "Command failed (rc=$rc): $*"
  return $rc
}

cleanup(){ :; }
trap cleanup EXIT

nm_has(){ nmcli -t -f NAME con show | grep -Fxq "$1"; }

load_bonding_module(){
  if ! lsmod | grep -q '^bonding'; then
    log_i "Loading bonding module"
    run modprobe bonding || { log_e "modprobe bonding failed"; return 1; }
  else
    log_i "Bonding module already loaded"
  fi
  if [[ ! -f /etc/modules-load.d/bonding.conf ]]; then
    echo bonding > /etc/modules-load.d/bonding.conf
    log_i "Configured bonding to load at boot"
  fi
}

ensure_wait_online(){
  # Don’t hard-require, just enable if available
  if systemctl list-unit-files | grep -q '^NetworkManager-wait-online.service'; then
    systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1 || run systemctl enable NetworkManager-wait-online.service
    systemctl is-active NetworkManager-wait-online.service  >/dev/null 2>&1 || run systemctl start  NetworkManager-wait-online.service
  fi
}

ensure_profiles(){
  # Make sure connections exist and slaves point to bond
  nm_has "$BOND_NAME" || { log_e "NM connection $BOND_NAME not found"; exit 1; }
  for s in "${SLAVES[@]}"; do
    nm_has "bond-slave-$s" || { log_e "NM connection bond-slave-$s not found"; exit 1; }
  done
  for s in "${SLAVES[@]}"; do
    if ! nmcli -g connection.master con show "bond-slave-$s" | grep -q "^$BOND_NAME$"; then
      log_w "Fixing master for bond-slave-$s -> $BOND_NAME"
      run nmcli con mod "bond-slave-$s" connection.master "$BOND_NAME" connection.slave-type bond
    fi
  done

  # Autoconnect=on everywhere
  for c in "$BOND_NAME" "${SLAVES[@]/#/bond-slave-}"; do
    nmcli -g connection.autoconnect con show "$c" | grep -q '^yes$' || run nmcli con mod "$c" connection.autoconnect yes
  done
}

enforce_bond_options(){
  case "$MODE" in
    802.3ad)
      # Strong, deterministic set
      local opts="mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer3+4,ad_select=stable,min_links=1"
      ;;
    active-backup)
      local primary="${SLAVES[0]}"
      local opts="mode=active-backup,miimon=100,primary=${primary},primary_reselect=always,fail_over_mac=active"
      ;;
    *) log_e "Unsupported --mode $MODE"; exit 1;;
  esac
  log_i "Setting bond options: $opts"
  run nmcli con mod "$BOND_NAME" bond.options "$opts"
}

maybe_disable_eee(){
  (( EEE_OFF == 1 )) || return 0
  for s in "${SLAVES[@]}"; do
    if command -v ethtool >/dev/null 2>&1; then
      run ethtool --set-eee "$s" eee off || true
    fi
  done
}

activate(){
  log_i "Bringing up $BOND_NAME and slaves"
  run nmcli con up "$BOND_NAME" || true
  for s in "${SLAVES[@]}"; do
    run nmcli con up "bond-slave-$s" || true
  done
}

bond_health(){
  # Returns 0 if healthy, 1 otherwise. Prints a brief summary.
  local f="/proc/net/bonding/$BOND_NAME"
  [[ -f $f ]] || { log_w "$BOND_NAME: bonding file missing"; return 1; }

  local mii_up agg_id ports partner slaves_agg same_agg=1 partner_ok=0
  mii_up=$(grep -m1 "^MII Status:" "$f" | awk '{print $3}')
  agg_id=$(awk '/^Active Aggregator Info:/{f=1;next} f&&/Aggregator ID:/ {print $3; exit}' "$f")
  ports=$(awk '/^Active Aggregator Info:/{f=1;next} f&&/Number of ports:/ {print $4; exit}' "$f")
  partner=$(awk '/^Active Aggregator Info:/{f=1;next} f&&/Partner Mac Address:/ {print $4; exit}' "$f")

  # Collect per-slave aggregator IDs and link states
  slaves_agg=()
  while IFS= read -r line; do
    slaves_agg+=("$line")
  done < <(awk '/^Slave Interface:/{s=$3} /^Aggregator ID:/ {print s":"$3}' "$f")

  # Validate
  [[ "$mii_up" == "up" ]] || { log_w "MII not up"; return 1; }
  [[ -n "$agg_id" ]] || { log_w "No active aggregator"; return 1; }
  [[ "${ports:-0}" -ge 1 ]] || { log_w "No ports in active aggregator"; return 1; }
  [[ "$partner" != "00:00:00:00:00:00" && -n "$partner" ]] && partner_ok=1

  # All slaves in same aggregator?
  for sa in "${slaves_agg[@]}"; do
    local sid="${sa%%:*}" said="${sa##*:}"
    if [[ "$said" != "$agg_id" ]]; then same_agg=0; fi
  done

  # Summarize
  log_i "Health: MII=$mii_up, AggID=$agg_id, Ports=$ports, Partner=$partner, SameAgg=$same_agg"
  if [[ "$MODE" == "802.3ad" ]]; then
    (( partner_ok == 1 && same_agg == 1 )) || return 1
  fi
  return 0
}

retry_until_healthy(){
  local deadline=$(( $(date +%s) + RETRY_SEC ))
  while (( $(date +%s) <= deadline )); do
    if bond_health; then return 0; fi
    log_w "Bond not healthy yet; retrying..."
    sleep 5
    activate
  done
  return 1
}

show_status(){
  if [[ -f /proc/net/bonding/$BOND_NAME ]]; then
    echo "=========================================="
    cat "/proc/net/bonding/$BOND_NAME"
    echo "=========================================="
  else
    log_w "$BOND_NAME not active"
  fi
}

main(){
  ensure_root
  log_i "Starting bond restore (mode=$MODE, retry=${RETRY_SEC}s, eee_off=$EEE_OFF)"
  load_bonding_module
  ensure_wait_online
  ensure_profiles
  enforce_bond_options
  maybe_disable_eee
  activate

  if retry_until_healthy; then
    log_i "✓ $BOND_NAME is healthy"
    nmcli -t -f NAME,TYPE,DEVICE con show --active | grep -E "(bond|enp3s0f)"
    exit 0
  else
    log_e "$BOND_NAME not healthy after ${RETRY_SEC}s"
    show_status
    journalctl -u NetworkManager --since "10 min ago" | grep -i -E "bond|lacp|team" || true
    exit 1
  fi
}

restart_nm(){
  ensure_root
  log_i "Restarting NetworkManager and reactivating bond"
  run systemctl restart NetworkManager
  sleep 5
  main
}

case "$ACTION" in
  main)     main;;
  status)   show_status;;
  restart)  restart_nm;;
esac
