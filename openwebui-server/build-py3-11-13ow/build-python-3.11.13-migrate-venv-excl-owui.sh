#!/usr/bin/env bash
# Build optimized Python 3.11.13 from source, export old venv packages,
# recreate venv, reinstall everything EXCEPT open-webui (always latest),
# and restart Open WebUI service. Supports --rollback to restore last venv.
#
# Host: Ubuntu 24.04 (T3600)
set -euo pipefail

# ------------------ Config ------------------
PY_VER="3.11.13"
PY_TARBALL="Python-${PY_VER}.tar.xz"
PY_DIR="Python-${PY_VER}"
PY_PREFIX="/opt/python-${PY_VER}"        # keep separate from system python
SRC_DIR="/usr/local/src"                 # source download/extract dir

OWUI_UNIT="openwebui.service"
OWUI_APP_ROOT="/home/randy/programs/py_progs/openwebui"
OLD_VENV="${OWUI_APP_ROOT}/venv"         # current venv to export from
NEW_VENV="${OWUI_APP_ROOT}/venv"         # new venv (same path)
OWUI_USER="randy"
OWUI_GROUP="randy"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUPS_DIR="${OWUI_APP_ROOT}/venv-backups"
EXPORTS_DIR="${OWUI_APP_ROOT}/venv-exports"
BACKUP_DIR="${BACKUPS_DIR}/${STAMP}"
EXPORT_DIR="${EXPORTS_DIR}/${STAMP}"

mkdir -p "${BACKUPS_DIR}" "${EXPORT_DIR}"

# ------------------ Helpers ------------------
need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
as_app_user(){ sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "$*"; }

rollback() {
  echo "==> ROLLBACK requested"
  systemctl stop "${OWUI_UNIT}" || true

  # Find the newest backup
  if [[ ! -d "${BACKUPS_DIR}" ]]; then
    echo "No backups folder at ${BACKUPS_DIR}"; exit 1
  fi
  local latest
  latest="$(ls -1dt "${BACKUPS_DIR}"/20* 2>/dev/null | head -n1 || true)"
  if [[ -z "${latest}" || ! -d "${latest}" ]]; then
    echo "No backup venvs found in ${BACKUPS_DIR}"; exit 1
  fi
  echo "Latest backup: ${latest}"

  # Move current venv aside (if present)
  if [[ -d "${OLD_VENV}" ]]; then
    local failed="${OLD_VENV}.failed.${STAMP}"
    echo "Moving current venv -> ${failed}"
    mv "${OLD_VENV}" "${failed}"
  fi

  echo "Restoring ${latest} -> ${OLD_VENV}"
  mv "${latest}" "${OLD_VENV}"
  chown -R "${OWUI_USER}:${OWUI_GROUP}" "${OLD_VENV}"

  systemctl start "${OWUI_UNIT}"
  systemctl status "${OWUI_UNIT}" --no-pager || true
  echo "==> ROLLBACK complete."
  exit 0
}

# ------------------ Args ------------------
if [[ "${1:-}" == "--rollback" ]]; then
  rollback
fi

# ------------------ Preflight ------------------
need_cmd wget; need_cmd tar; need_cmd make; need_cmd gcc; need_cmd systemctl; need_cmd curl
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0"; exit 1
fi

echo "==> Installing build prerequisites (incl. liblzma-dev for _lzma)"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  build-essential make wget curl ca-certificates \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses-dev libffi-dev libgdbm-dev libgdbm-compat-dev \
  liblzma-dev xz-utils tk-dev uuid-dev

# ------------------ 1) Export old venv ------------------
if [[ -d "${OLD_VENV}" ]]; then
  echo "==> Exporting packages from OLD venv: ${OLD_VENV}"
  as_app_user "
    source '${OLD_VENV}/bin/activate'
    python -V > '${EXPORT_DIR}/python-version.txt' 2>&1 || true
    pip --version > '${EXPORT_DIR}/pip-version.txt'
    pip freeze > '${EXPORT_DIR}/requirements.freeze.txt'
    pip list --format=columns > '${EXPORT_DIR}/pip-list.txt'
    pip list --outdated || true > '${EXPORT_DIR}/pip-outdated.txt'
  "
  # Filter out open-webui for reinstall (we'll install latest separately)
  # Handle variations: open-webui, open_webui, direct VCS/URL lines that start with those names.
  awk '
    BEGIN{IGNORECASE=1}
    !/^(open-webui|open_webui)([[:space:]]|==|@|$)/
  ' "${EXPORT_DIR}/requirements.freeze.txt" > "${EXPORT_DIR}/requirements.freeze.no-openwebui.txt"
  echo "==> Export (full):    ${EXPORT_DIR}/requirements.freeze.txt"
  echo "==> Export (filtered) ${EXPORT_DIR}/requirements.freeze.no-openwebui.txt"
else
  echo "!! Old venv not found at ${OLD_VENV}; will create fresh on new Python."
fi

# ------------------ 2) Build Python (PGO + LTO) ------------------
mkdir -p "${SRC_DIR}"
cd "${SRC_DIR}"

if [[ ! -f "${PY_TARBALL}" ]]; then
  echo "==> Downloading ${PY_TARBALL} from python.org"
  wget -q "https://www.python.org/ftp/python/${PY_VER}/${PY_TARBALL}"
fi
[[ -f "${PY_TARBALL}" ]] || { echo "Tarball not found: ${PY_TARBALL}"; exit 1; }

rm -rf "${PY_DIR}"
echo "==> Extracting ${PY_TARBALL}"
tar -xf "${PY_TARBALL}"
cd "${PY_DIR}"

echo "==> Configuring Python ${PY_VER} with --enable-optimizations --with-lto --prefix=${PY_PREFIX}"
./configure --prefix="${PY_PREFIX}" --enable-optimizations --with-lto

CORES="$(nproc || echo 2)"
echo "==> Building Python (using ${CORES} cores)"
make -j"${CORES}"

echo "==> Installing via make altinstall (won't touch system /usr/bin/python3)"
make altinstall

NEW_PY="${PY_PREFIX}/bin/python3.11"
NEW_PIP="${PY_PREFIX}/bin/pip3.11"
[[ -x "${NEW_PY}" ]] || { echo "New Python not found at ${NEW_PY}"; exit 1; }

# Convenience symlinks
[[ -e /usr/local/bin/python3.11 ]] || ln -s "${NEW_PY}" /usr/local/bin/python3.11
[[ -e /usr/local/bin/pip3.11    ]] || ln -s "${NEW_PIP}" /usr/local/bin/pip3.11

echo "==> Installed: $(${NEW_PY} --version)"

# ------------------ 3) Stop service & backup venv ------------------
echo "==> Stopping ${OWUI_UNIT}"
systemctl stop "${OWUI_UNIT}"

if [[ -d "${OLD_VENV}" ]]; then
  echo "==> Backing up old venv to ${BACKUP_DIR}"
  mv "${OLD_VENV}" "${BACKUP_DIR}"
fi

# ------------------ 4) Recreate venv & reinstall ------------------
echo "==> Creating new venv with ${NEW_PY} at ${NEW_VENV}"
as_app_user "'${NEW_PY}' -m venv '${NEW_VENV}'"

echo "==> Upgrading installer tooling in new venv"
as_app_user "
  source '${NEW_VENV}/bin/activate'
  python -m pip install --upgrade pip setuptools wheel
"

REQ_NO_OWUI="${EXPORT_DIR}/requirements.freeze.no-openwebui.txt"
if [[ -f "${REQ_NO_OWUI}" ]]; then
  echo "==> Reinstalling packages (excluding open-webui) from ${REQ_NO_OWUI}"
  as_app_user "
    source '${NEW_VENV}/bin/activate'
    pip install --no-input -r '${REQ_NO_OWUI}'
  "
else
  echo "!! No exported requirements found; proceeding without bulk reinstall."
fi

echo "==> Installing LATEST open-webui"
as_app_user "
  source '${NEW_VENV}/bin/activate'
  pip install --upgrade open-webui
"

# Ensure ownership
chown -R "${OWUI_USER}:${OWUI_GROUP}" "${PY_PREFIX}"
chown -R "${OWUI_USER}:${OWUI_GROUP}" "${NEW_VENV}"

# ------------------ 5) Restart & verify _lzma ------------------
echo "==> Restarting ${OWUI_UNIT}"
systemctl daemon-reload
systemctl start "${OWUI_UNIT}"
systemctl status "${OWUI_UNIT}" --no-pager || true

echo "==> Verifying _lzma in the NEW venv"
as_app_user "
  source '${NEW_VENV}/bin/activate'
  python - <<'PY'
import sys
try:
    import lzma
    print('Python:', sys.version)
    print('lzma OK:', lzma.LZMADecompressor is not None)
except Exception as e:
    print('lzma import FAILED:', e)
    raise
PY
"

echo "==> Done."
echo "Backup venv: ${BACKUP_DIR}"
echo "Exports:     ${EXPORT_DIR}/requirements.freeze.txt (full)"
echo "             ${EXPORT_DIR}/requirements.freeze.no-openwebui.txt (filtered)"
echo "Rollback:    sudo $0 --rollback"
