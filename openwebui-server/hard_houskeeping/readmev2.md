Here's the updated `README.md`, integrating all the requested **Optional Hardening & Housekeeping** content with clean, copy‑paste-ready snippets. It includes back-up strategies, reverse‑proxy configuration, systemd drop-ins, and maintenance tips — all sourced from official Open WebUI documentation.

---

````markdown
# Open WebUI Environment Setup & Maintenance

Set up a secure, upgrade-resilient Open WebUI environment on Ubuntu (or a similar system), with Python built from source, robust backups, Nginx proxying, and health monitoring.

---

##  Prerequisites

- Ubuntu 24.04 (x86_64) or equivalent
- Bash shell and elevated (sudo) access
- A dedicated system user for running Open WebUI (e.g., `appuser`)

---

##  Setup & Migration Scripts

| Step | Tool / Script | Purpose |
|------|----------------|---------|
| 1 | `build-python-3.11.13-migrate-venv-excl-owui.sh` | Build optimized Python 3.11.13, recreate venv (all packages except `open-webui`), and install latest `open-webui` |
| 1b | `--rollback` flag on the above script | Restore the prior venv from backup if needed |
| 2 | `owui-diagnosev3.sh` | Diagnose current installation and environment |
| 3 | `owui-healthcheck.sh` | Health-check script to verify service status, `/health` endpoint, and logs |

---

##  Optional Hardening & Housekeeping

###  Backups (File-Level)

Open WebUI’s persistent data (`webui.db`, `uploads/`, `vector_db/`, `cache/`, `audit.log`) resides in your configured `DATA_DIR` (e.g., `/var/lib/open-webui`).

A nightly `rsync` backup is sufficient:

```bash
#!/usr/bin/env bash
set -e
SOURCE="/var/lib/open-webui"
DEST="/backup/open-webui-$(date +%F)"
rsync -a --delete --exclude='cache/' "$SOURCE/" "$DEST/"
````

Or use `tar` for periodic full snapshots:

```bash
tar -C /var/lib/open-webui -czf ~/openwebui-backup-$(date +%F).tgz .
```

**Restore example:**

```bash
sudo systemctl stop openwebui.service
sudo rsync -a --delete /backup/open-webui-2025-08-16/ /var/lib/open-webui/
sudo chown -R appuser:appuser /var/lib/open-webui
sudo systemctl start openwebui.service
```

Source: Open WebUI backup documentation ([� docs.openwebui.com](https://docs.openwebui.com/tutorials/maintenance/backups/?utm_source=chatgpt.com)) ([Open WebUI][1], [Vultr Docs][2], [SUSE Documentation][3])

---

### Reverse Proxy & `WEBUI_URL`

Use Nginx to forward public traffic to `127.0.0.1:5000`, and set `WEBUI_URL` to your public domain so internal links and OAuth redirect URIs align.

```nginx
server {
    listen 80;
    server_name your.domain;

    client_max_body_size 100M;
    proxy_read_timeout  3600s;
    proxy_send_timeout  3600s;

    location / {
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade           $http_upgrade;
        proxy_set_header Connection        "upgrade";

        proxy_pass http://127.0.0.1:5000;
    }
}
```

Enable and reload Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

This ensures proper domain mapping in generated links and integrations.

---

### Systemd & Environment Variables

Manage environment variables like `DATA_DIR`, `WEBUI_URL`, and `WEBUI_SECRET_KEY` via a systemd drop‑in:

**Unit file:**

```ini
# /etc/systemd/system/openwebui.service
[Unit]
Description=Open WebUI Service
After=network.target

[Service]
Type=simple
User=appuser
Group=appuser
WorkingDirectory=/opt/openwebui/app
ExecStart=/opt/openwebui/venv/bin/open-webui serve --port 5000
Restart=on-failure
Environment=VIRTUAL_ENV=/opt/openwebui/venv
Environment=PATH=/opt/openwebui/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

[Install]
WantedBy=multi-user.target
```

**Drop-in:**

```ini
# /etc/systemd/system/openwebui.service.d/10-env.conf
[Service]
Environment=DATA_DIR=/var/lib/open-webui
Environment=WEBUI_URL=https://your.domain
# Optional for session persistence:
# Environment=WEBUI_SECRET_KEY=<random-32-char-string>
```

Reload and restart:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openwebui.service
sudo systemctl status openwebui.service --no-pager
```

Persistent configuration variables impact your setup long-term; external environment changes need to align with documentation. ([GitHub][4], [Open WebUI][5])

---

### SQLite Maintenance (Optional)

Install `sqlite3` to periodically check DB integrity:

```bash
sudo apt install sqlite3
sqlite3 /var/lib/open-webui/webui.db "PRAGMA integrity_check;"
sqlite3 /var/lib/open-webui/webui.db "VACUUM;"
```

---

### Health Monitoring

Use the `/health` endpoint to monitor service status:

```bash
curl -fsS https://your.domain/health || echo "Service is unhealthy"
```

For local health probes:

```bash
curl -fsS http://127.0.0.1:5000/health || echo "Local instance down"
```

---

## Recovery & Rollback

If an upgrade fails, roll back to the latest venv backup:

```bash
sudo ./build-python-3.11.13-migrate-venv-excl-owui.sh --rollback
```

This stops your service, restores the last backup venv, and restarts your instance cleanly.

---

## References

* **Backups**: Open WebUI file-level backup docs ([SUSE Documentation][3], [Open WebUI][1])
* **Env vars**: Comprehensive reference & `PersistentConfig` behavior ([Open WebUI][5])
* **Advanced config, HTTPS, monitoring**: Open WebUI advanced topics hub ([Open WebUI][6])

---

## TL;DR Setup Workflow

1. Run `build-python-3.11.13-migrate-venv-excl-owui.sh`
2. Confirm success and service health via `owui-healthcheck.sh`
3. Set up Nginx proxy and `.service.d` environment config
4. Schedule backups (rsync/tar)
5. Monitor `/health` endpoint
6. When needed, rollback via `--rollback`

---

Feel free to customize paths, user names, or scheduling mechanisms as needed. Let me know if you'd like ready-to-use scripts for cron scheduling, rollback dashboards, or backup rotation!

[1]: https://docs.openwebui.com/tutorials/maintenance/backups/?utm_source=chatgpt.com "Backups"
[2]: https://docs.vultr.com/how-to-install-open-webui-an-opensource-web-interface-for-running-llms?utm_source=chatgpt.com "How to Install Open WebUI - An Opensource Web Interface ..."
[3]: https://documentation.suse.com/suse-ai/1.0/html/openwebui-configuring/index.html?utm_source=chatgpt.com "Configuring Open WebUI for AI Interaction"
[4]: https://github.com/open-webui/open-webui/discussions/9261?utm_source=chatgpt.com "Environment Variables #9261"
[5]: https://docs.openwebui.com/getting-started/env-configuration/?utm_source=chatgpt.com "Environment Variable Configuration"
[6]: https://docs.openwebui.com/getting-started/advanced-topics/?utm_source=chatgpt.com "Advanced Topics"
