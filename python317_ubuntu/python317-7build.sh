#!/usr/bin/env bash
# Build and install CPython 3.13.7 with PGO+LTO on Ubuntu/Xubuntu 22.04
# Installs to /opt/python-3.13.7 and does NOT replace system python3.
# Docs: build deps (Debian/Ubuntu) & configure flags. See links in README/comments.

set -Eeuo pipefail

PY_VER="3.13.7"
PREFIX="/opt/python-${PY_VER}"
SRC_ROOT="/usr/local/src"
TARBALL="Python-${PY_VER}.tar.xz"
BASE_URL="https://www.python.org/ftp/python/${PY_VER}"
URL="${BASE_URL}/${TARBALL}"
SIG_URL="${URL}.asc"       # optional: GPG signature
NPROC="$(nproc || echo 1)"

echo "==> Preparing to build Python ${PY_VER} into ${PREFIX}"

# 0) Require root for system installs (apt, /opt install, ldconfig, /usr/local/bin symlinks)
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (e.g. sudo $0)"; exit 1
fi

# 1) Build prerequisites (based on CPython devguide for Debian/Ubuntu)
#    If 'deb-src' isn’t enabled you might skip 'build-dep'. We install
#    an explicit, conservative set of -dev packages to cover stdlib modules.
echo "==> Installing build dependencies…"
apt-get update -y
# Try to pull distro build-deps first (ok if this fails)
apt-get build-dep -y python3 || true
# Core toolchain & libraries
DEPS=(
  build-essential gdb lcov pkg-config
  wget curl ca-certificates xz-utils tk-dev
  libbz2-dev libffi-dev libgdbm-dev libgdbm-compat-dev
  liblzma-dev libncurses5-dev libreadline-dev
  libsqlite3-dev libssl-dev zlib1g-dev
  libnss3-dev libexpat1-dev libmpdec-dev libuuid-dev
)
apt-get install -y --no-install-recommends "${DEPS[@]}"

# 2) Fetch sources (with optional GPG signature for verification)
mkdir -p "${SRC_ROOT}"
cd "${SRC_ROOT}"
if [[ ! -f "${TARBALL}" ]]; then
  echo "==> Downloading ${TARBALL}"
  wget -q "${URL}"
fi

# Optional: verify with GPG if you have the release manager’s key imported.
# See: https://www.python.org/downloads/release/python-3137/ (SIG link) and
# signature verification notes: https://www.python.org/downloads/metadata/pgp/
if command -v gpg >/dev/null; then
  echo "==> (Optional) Verifying GPG signature (will skip if signature/key unavailable)…"
  if wget -q -O "${TARBALL}.asc" "${SIG_URL}"; then
    # This will say "Good signature" if your keyring has the right PSF RM key.
    # If not, import the RM key from a trusted source before re-running.
    set +e
    gpg --verify "${TARBALL}.asc" "${TARBALL}"
    GPG_RC=$?
    set -e
    if [[ $GPG_RC -ne 0 ]]; then
      echo "!! GPG verification not completed. Consider importing the correct release manager key."
      echo "   See: https://www.python.org/downloads/metadata/pgp/ and Sigstore: https://www.python.org/downloads/metadata/sigstore/"
    fi
  fi
fi

# 3) Unpack
echo "==> Extracting sources…"
rm -rf "Python-${PY_VER}"
tar -xf "${TARBALL}"
cd "Python-${PY_VER}"

# 4) Configure with PGO+LTO; ensure shared lib; ensurepip installs pip
echo "==> Configuring…"
./configure \
  --prefix="${PREFIX}" \
  --enable-optimizations \
  --with-lto \
  --enable-shared \
  --with-ensurepip=install

# 5) Build using all cores (PGO step runs automatically with --enable-optimizations)
echo "==> Building (using ${NPROC} jobs)…"
make -j "${NPROC}"

# 6) Install without clobbering /usr/local/bin/python3
#    'altinstall' avoids creating the unversioned 'python3' and 'pip3' symlinks.
echo "==> Installing (altinstall)…"
make altinstall

# 7) Link versioned binaries for convenience and configure ld.so for libpython
echo "==> Linking python3.13 and pip3.13 into /usr/local/bin…"
ln -sf "${PREFIX}/bin/python3.13" /usr/local/bin/python3.13
ln -sf "${PREFIX}/bin/pip3.13"    /usr/local/bin/pip3.13 || true

# Shared lib path
echo "==> Registering ${PREFIX}/lib in dynamic linker config…"
echo "${PREFIX}/lib" >/etc/ld.so.conf.d/python-${PY_VER}.conf
ldconfig

# 8) Upgrade pip / wheel / setuptools in the new interpreter
echo "==> Upgrading pip/setuptools/wheel in the new Python…"
"${PREFIX}/bin/python3.13" -m pip install --upgrade pip setuptools wheel

# 9) Show result
echo
echo "==> Done. Installed:"
echo "    $(/usr/local/bin/python3.13 -V)   (from ${PREFIX})"
echo "    which python3.13 -> $(command -v python3.13)"
echo
echo "Create a venv (optional):"
echo "    python3.13 -m venv \$HOME/py313"
echo "    source \$HOME/py313/bin/activate"
