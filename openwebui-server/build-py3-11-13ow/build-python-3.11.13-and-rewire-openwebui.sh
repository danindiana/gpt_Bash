#!/usr/bin/env bash
# Build optimized Python 3.11.13 from source and rewire Open WebUI venv
# For host: Ubuntu 24.04 (T3600)
# This uses: --enable-optimizations --with-lto and make altinstall

set -euo pipefail

PY_VER="3.11.13"
PY_TARBALL="Python-${PY_VER}.tar.xz"
PY_DIR="Python-${PY_VER}"
PY_PREFIX="/opt/python-${PY_VER}"          # install prefix (kept separate from system python)
SRC_DIR="/usr/local/src"                   # where we download/extract sources

# Open WebUI specifics (adjust if your paths change)
OWUI_UNIT="openwebui.service"
OWUI_APP_ROOT="/home/randy/programs/py_progs/openwebui"
OWUI_VENV="${OWUI_APP_ROOT}/venv"          # current venv path (will be replaced)
OWUI_USER="randy"
OWUI_GROUP="randy"

# Safety: ensure we're root (we use apt, write to /opt, manage systemd)
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "==> Installing build prerequisites (including liblzma-dev for _lzma)"
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
  build-essential make wget curl ca-certificates \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncurses-dev libffi-dev libgdbm-dev libgdbm-compat-dev \
  liblzma-dev xz-utils tk-dev uuid-dev

mkdir -p "${SRC_DIR}"
cd "${SRC_DIR}"

# Download official Python source (3.11.13)
if [[ ! -f "${PY_TARBALL}" ]]; then
  echo "==> Downloading ${PY_TARBALL} from python.org"
  # Primary source (official)
  wget -q "https://www.python.org/ftp/python/${PY_VER}/${PY_TARBALL}"
fi

# Verify tarball exists
[[ -f "${PY_TARBALL}" ]] || { echo "Tarball not found: ${PY_TARBALL}"; exit 1; }

# Extract
rm -rf "${PY_DIR}"
echo "==> Extracting ${PY_TARBALL}"
tar -xf "${PY_TARBALL}"

cd "${PY_DIR}"

# Configure for optimized build (PGO+LTO)
# --enable-optimizations triggers PGO; --with-lto enables link-time optimization
echo "==> Configuring Python ${PY_VER} with --enable-optimizations --with-lto --prefix=${PY_PREFIX}"
./configure --prefix="${PY_PREFIX}" --enable-optimizations --with-lto

# Build using all cores
CORES="$(nproc || echo 2)"
echo "==> Building (this may take several minutes; using ${CORES} cores)"
make -j"${CORES}"

# Install without clobbering system python
echo "==> Installing via make altinstall to avoid replacing system python"
make altinstall

# Ensure new python is visible for this session
NEW_PY="${PY_PREFIX}/bin/python3.11"
NEW_PIP="${PY_PREFIX}/bin/pip3.11"
[[ -x "${NEW_PY}" ]] || { echo "New Python not found at ${NEW_PY}"; exit 1; }

# Optionally add convenience symlinks (does not touch /usr/bin/python3)
if [[ ! -e /usr/local/bin/python3.11 ]]; then
  ln -s "${NEW_PY}" /usr/local/bin/python3.11
fi
if [[ ! -e /usr/local/bin/pip3.11 ]]; then
  ln -s "${NEW_PIP}" /usr/local/bin/pip3.11
fi

echo "==> Python installed at ${PY_PREFIX}"
"${NEW_PY}" --version

# Rebuild Open WebUI venv on the new interpreter
echo "==> Stopping ${OWUI_UNIT} to rebuild its virtualenv cleanly"
systemctl stop "${OWUI_UNIT}"

# Backup existing venv in case you want to roll back quickly
STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -d "${OWUI_VENV}" ]]; then
  echo "==> Backing up current venv -> ${OWUI_VENV}.bak.${STAMP}"
  mv "${OWUI_VENV}" "${OWUI_VENV}.bak.${STAMP}"
fi

echo "==> Creating new venv with ${NEW_PY}"
sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" "${NEW_PY}" -m venv "${OWUI_VENV}"

# Upgrade pip/setuptools/wheel and reinstall Open WebUI
echo "==> Upgrading pip/setuptools/wheel and reinstalling open-webui"
sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
  source '${OWUI_VENV}/bin/activate'
  python -m pip install --upgrade pip setuptools wheel
  pip install --upgrade open-webui
  # Optional: re-install any extras you use, e.g. 'pip install psycopg2-binary' for Postgres, etc.
"

# Ensure ownership on /opt prefix and venv bits
chown -R "${OWUI_USER}:${OWUI_GROUP}" "${PY_PREFIX}"
chown -R "${OWUI_USER}:${OWUI_GROUP}" "${OWUI_VENV}"

echo "==> Restarting ${OWUI_UNIT}"
systemctl daemon-reload
systemctl start "${OWUI_UNIT}"
systemctl status "${OWUI_UNIT}" --no-pager

echo "==> Verifying _lzma is available in the new venv"
sudo -u "${OWUI_USER}" -g "${OWUI_GROUP}" bash -lc "
  source '${OWUI_VENV}/bin/activate'
  python - <<'PY'
import sys, lzma
print('Python:', sys.version)
print('lzma OK:', lzma.LZMADecompressor is not None)
PY
"

echo "==> Done."
echo "Tip: keep ${PY_PREFIX} and your system Python separate; that's why we used make altinstall."
