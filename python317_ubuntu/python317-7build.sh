#!/usr/bin/env bash
# build-python-3.13.7.sh — Ubuntu 22.04 (Jammy)
# Build CPython 3.13.7 with PGO+LTO into /opt/python-3.13.7 safely (side-by-side).

set -Eeuo pipefail

PY_VER="3.13.7"
PREFIX="/opt/python-${PY_VER}"
SRC_ROOT="/usr/local/src"
TARBALL="Python-${PY_VER}.tar.xz"
URL="https://www.python.org/ftp/python/${PY_VER}/${TARBALL}"
NPROC="$(nproc || echo 1)"

if [[ $EUID -ne 0 ]]; then echo "Please run as root (sudo $0)"; exit 1; fi

echo "==> Installing toolchain & headers…"
apt-get update -y

# Best-effort: only run build-dep if deb-src is enabled
if grep -Rq '^[[:space:]]*deb-src' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  apt-get build-dep -y python3 || true
fi

# Explicit deps for common stdlib modules (Jammy names)
apt-get install -y --no-install-recommends \
  build-essential gdb lcov pkg-config \
  wget curl ca-certificates xz-utils tk-dev \
  libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev \
  liblzma-dev libncurses5-dev libreadline-dev \
  libsqlite3-dev libssl-dev zlib1g-dev \
  libnss3-dev libexpat1-dev libmpdec-dev uuid-dev

mkdir -p "${SRC_ROOT}" && cd "${SRC_ROOT}"
[[ -f "${TARBALL}" ]] || wget -q "${URL}"

echo "==> Extracting…"
rm -rf "Python-${PY_VER}"
tar -xf "${TARBALL}"
cd "Python-${PY_VER}"

echo "==> Configuring (PGO+LTO, shared lib)…"
./configure \
  --prefix="${PREFIX}" \
  --enable-optimizations \
  --with-lto \
  --enable-shared \
  --with-ensurepip=install

echo "==> Building with ${NPROC} jobs…"
make -j "${NPROC}"

echo "==> Installing (altinstall)…"
make altinstall

echo "==> Linking convenience wrappers…"
ln -sf "${PREFIX}/bin/python3.13" /usr/local/bin/python3.13
ln -sf "${PREFIX}/bin/pip3.13"    /usr/local/bin/pip3.13 || true

echo "==> Registering lib path…"
echo "${PREFIX}/lib" >/etc/ld.so.conf.d/python-${PY_VER}.conf
ldconfig

echo "==> Upgrading pip/setuptools/wheel…"
"${PREFIX}/bin/python3.13" -m pip install --upgrade pip setuptools wheel

echo
echo "Installed: $(/usr/local/bin/python3.13 -V) from ${PREFIX}"
echo "Create a venv:"
echo "  python3.13 -m venv \$HOME/py313 && source \$HOME/py313/bin/activate"
