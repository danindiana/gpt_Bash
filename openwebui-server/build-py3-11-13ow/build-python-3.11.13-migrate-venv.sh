#!/usr/bin/env bash
# Build optimized Python 3.11.13 from source, export old venv packages,
# recreate venv, reinstall EXACT packages, and restart Open WebUI service.
# Host: Ubuntu 24.04 (T3600)

set -euo pipefail

PY_VER="3.11.13"
PY_TARBALL="Python-${PY_VER}.tar.xz"
PY_DIR="Python-${PY_VER}"
PY_PREFIX="/opt/python-${PY_VER}"           # install prefix (kept separate from system python)
SRC_DIR="/usr/local/src"                    # source download/extract dir

# Open WebUI specifics (adjust if your paths change)
OWUI_UNIT="openwebui.service"
OWUI_APP_ROOT="/home/randy/programs/py_progs/openwebui"
OLD_VENV="${OWUI_APP_ROOT}/venv"            # current venv to export from
NEW_VENV="${OWUI_APP_ROOT}/venv"            # new venv (same path)
OWUI_USER="randy"
OWUI_GROUP="randy"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${OWUI_APP_ROOT}/venv-backups/${STAMP}"
EXPORT_DIR="${OWUI_APP_ROOT}/venv-exports/${STAMP}"
mkdir -p "${EXPORT_DIR}" "${OWUI_APP_ROOT}/venv-backups"

need_cmd(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }

echo "==> Preflight checks"
need_cmd wget
need_cmd tar
need_cmd make
need_cmd gcc
need_cmd systemctl
need_cmd curl
# `pip` is invoked via the venv interpreters; not required globally.

echo "==> Installing build prerequisites (incl. liblzma-dev for _lzma)"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  build-essential make wget curl ca-certificates \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses-dev libffi-dev libgdbm-dev libgdbm-compat-dev \
  liblzma-dev xz-utils tk-dev uuid-dev

# -----------------------------
# 1) EXPORT OLD VENV PACKAGES
# -----------------------------
if [[ -d "${OLD_VENV}" ]]; then
  echo "==> Exporting package list from OLD venv: ${OLD_VENV}"
  # Use the OLD venv's python/pip to avoid path surprises
  sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
    source '${OLD_VENV}/bin/activate'
    python -V > '${EXPORT_DIR}/python-version.txt' 2>&1 || true
    pip --version > '${EXPORT_DIR}/pip-version.txt'
    # Full, pinned set (transitives included) to faithfully reproduce env:
    pip freeze > '${EXPORT_DIR}/requirements.freeze.txt'
    # Extra context (not used for reinstall, just a human report):
    pip list --format=columns > '${EXPORT_DIR}/pip-list.txt'
    pip list --outdated || true > '${EXPORT_DIR}/pip-outdated.txt'
  "
  echo "==> Export saved to ${EXPORT_DIR}"
else
  echo "!! Old venv not found at ${OLD_VENV}; will create fresh on new Python."
fi

# ---------------------------------
# 2) BUILD PYTHON 3.11.13 (PGO+LTO)
# ---------------------------------
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

# --------------------------------------------
# 3) STOP SERVICE, BACKUP VENV, RECREATE VENV
# --------------------------------------------
echo "==> Stopping ${OWUI_UNIT}"
systemctl stop "${OWUI_UNIT}"

if [[ -d "${OLD_VENV}" ]]; then
  echo "==> Backing up old venv to ${BACKUP_DIR}"
  mkdir -p "${BACKUP_DIR%/*}"
  mv "${OLD_VENV}" "${BACKUP_DIR}"
fi

echo "==> Creating new venv with ${NEW_PY} at ${NEW_VENV}"
sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" "${NEW_PY}" -m venv "${NEW_VENV}"

echo "==> Upgrading installer tooling in new venv"
sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
  source '${NEW_VENV}/bin/activate'
  python -m pip install --upgrade pip setuptools wheel
"

# ----------------------------------------------
# 4) REINSTALL EXACT PACKAGES FROM OLD FREEZE
# ----------------------------------------------
REQ_FILE="${EXPORT_DIR}/requirements.freeze.txt"
if [[ -f "${REQ_FILE}" ]]; then
  echo "==> Reinstalling packages from ${REQ_FILE}"
  sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
    source '${NEW_VENV}/bin/activate'
    # Install EXACT pins (transitive deps included) for a faithful clone.
    # NOTE: This may take a while and may build wheels for some packages.
    pip install --no-input -r '${REQ_FILE}'
  "
else
  echo "!! No exported requirements found; installing open-webui only"
  sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
    source '${NEW_VENV}/bin/activate'
    pip install --upgrade open-webui
  "
fi

# Ensure ownership
chown -R "${OWUI_USER}:${OWUI_GROUP}" "${PY_PREFIX}"
chown -R "${OWUI_USER}:${OWUI_GROUP}" "${NEW_VENV}"

# ----------------------------------------------
# 5) RESTART SERVICE & VERIFY _lzma AVAILABILITY
# ----------------------------------------------
echo "==> Restarting ${OWUI_UNIT}"
systemctl daemon-reload
systemctl start "${OWUI_UNIT}"
systemctl status "${OWUI_UNIT}" --no-pager

echo "==> Verifying _lzma in the NEW venv"
sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
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

echo "==> Done. Old venv backup: ${BACKUP_DIR}"
echo "    Exported packages:     ${EXPORT_DIR}/requirements.freeze.txt"
