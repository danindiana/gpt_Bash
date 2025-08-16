# Open WebUI Environment Setup & Migration

This guide outlines how to set up a reliable and upgrade-safe Open WebUI environment on *Ubuntu 24.04 (or similar)*, including building Python 3.11.13 from source, preserving data across upgrades, and managing rollback scenarios.

> **Note:** Replace `<YOUR_SYSTEM>` placeholders with your actual values (e.g. OS version, system user, paths).

---

##  Prerequisites

- Machine running **Ubuntu 24.04 (x86_64 recommended)**
- Bash-compatible shell (e.g., `bash` CLI)
- Root or sudo privileges
- Target user (e.g., `randy`) for application execution

---

##  Setup & Migration Scripts

| Step | Purpose | Script |
|------|---------|--------|
| 0a   | Build optimized Python 3.11.13 (PGO + LTO, includes `_lzma`) | `build-python-3.11.13-migrate-venv-excl-owui.sh` |
| 0b   | [Optional] Roll back to last known venv snapshot if needed | `--rollback` flag of the same script |
| 1    | Health-check tool for daily monitoring | `owui-healthcheck.sh` |
| 2    | Migration script excluding `open-webui`, retains all other packages, and installs latest Open WebUI | Part of the above build script |
| 3    | Diagnostic script to inspect system state and confirm config | `owui-diagnosev3.sh` |

---

##  Cold-Start Setup Procedure

1. **Run the build-and-migrate script** to compile Python from source and recreate the Open WebUI venv:
   ```bash
   chmod +x build-python-3.11.13-migrate-venv-excl-owui.sh
   sudo ./build-python-3.11.13-migrate-venv-excl-owui.sh
