```mermaid
flowchart TD
  A[Start: Symptoms] --> A1{Issue area?}
  A1 -->|Ollama/GPU| G0
  A1 -->|Nginx/Certbot| N0

  %% =======================
  %% GPU / OLLAMA TRACK
  %% =======================
  subgraph G[GPU / Ollama not using NVIDIA]
    direction TB
    G0[Check nvidia-smi\nsee GPUs & no running procs] --> G1[Run Ollama in debug\nOLLAMA_LOG_LEVEL=debug ollama serve]
    G1 --> G2{CUDA init OK?}
    G2 -- no --> G3[Check kernel modules\nlsmod for nvidia,nvidia_uvm]
    G3 --> G4[Check /dev nodes\n/dev/nvidia0,1,ctl,uvm present]
    G4 --> G5[Check driver libs\nldconfig for libcuda.so & libnvidia-ml.so]
    G5 --> G6[Sanity: cuInit via Python\ncuDeviceGetCount > 0]
    G2 -- yes --> G7[Confirm Ollama API up on 11434\nno stray process]
    G7 --> G8{Multi-GPU desired?}
    G8 -- no --> G9[Prefer single larger VRAM GPU\nset CUDA_VISIBLE_DEVICES to that one]
    G8 -- yes --> G10[systemd override:\nCUDA_VISIBLE_DEVICES=0,1\nOLLAMA_LLM_LIBRARY=cuda\nOLLAMA_NUM_GPU_LAYERS=999\nOLLAMA_SCHED_SPREAD=true]
    G10 --> G11[Allow devices in cgroup:\nDeviceAllow=/dev/nvidia0, /dev/nvidia1,\n/dev/nvidiactl, /dev/nvidia-uvm]
    G11 --> G12[daemon-reload & restart service]
    G12 --> G13[Trigger tiny generate to load model]
    G13 --> G14[Watch nvidia-smi\nVRAM appears on both GPUs?]
    G14 -->|yes| G15[✅ Multi-GPU active]
    G14 -->|no| G16[Re-check env applied:\n systemctl show ollama grep Environment\nOrder bigger VRAM first]
  end

  %% =======================
  %% NGINX / CERTBOT TRACK
  %% =======================
  subgraph N[Nginx / Certbot / DuckDNS]
    direction TB
    N0[nginx -t as root] --> N1{Conflicts on :80?}
    N1 -- yes --> N2[Remove duplicate server blocks\nfor same server_name]
    N1 -- no --> N3[Add explicit ACME location\n/.well-known/acme-challenge -> alias /var/www/letsencrypt-challenges/]
    N2 --> N3
    N3 --> N4[Create test file 'health'\nunder webroot; test with Host header\ncurl -H 'Host: domain' 127.0.0.1/.well-known/.../health == 'test']
    N4 --> N5{Public DNS & WAN match?}
    N5 -- no --> N6[Update DuckDNS A to WAN IPv4; optionally clear AAAA if not serving v6]
    N6 --> N5
    N5 -- yes --> N7{Can open port 80?}
    N7 -- yes --> N8[Certbot webroot HTTP-01\ncertbot certonly --webroot ...]
    N7 -- no --> N9[Use DNS-01 with DuckDNS token\nmanual auth/cleanup hooks]
    N8 --> N10
    N9 --> N10[Cert issued\nfiles in /etc/letsencrypt/live/domain/]
    N10 --> N11[Install HTTPS server block 443\npoint to fullchain.pem & privkey.pem]
    N11 --> N12[HTTP -> HTTPS redirect site\nkeep ACME location on HTTP]
    N12 --> N13[Reload nginx as root]
    N13 --> N14[Verify HTTPS:\n curl -I --resolve domain:443:127.0.0.1 https://domain/]
    N14 --> N15[Add renew hook to reload nginx\n/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh]
    N15 --> N16[✅ TLS working end-to-end]
  end

  %% JOIN
  G15 --> Z[Done]
  G16 --> Z
  N16 --> Z[Done]
```

What we troubleshot (in rough order)
Ollama not using GPU

CUDA init failing inside Ollama with error 999 (“unknown error”) → typically driver/lib or device node/permissions issue. 
NVIDIA Developer Forums
+1

Verified CUDA stack works outside Ollama (cuInit(0) OK via Python).

Found a stale Ollama process binding 11434; killed it and restarted clean.

Confirmed NVIDIA modules & /dev nodes present (nvidia, nvidia_uvm, nvidia0/1, nvidiactl).

Ensured runtime libs present (libcuda.so, libnvidia-ml.so, libcublas.so).

Reinstalled Ollama, ran foreground with debug to see CUDA probing.

Systemd service env not exposing GPUs properly → fixed CUDA_VISIBLE_DEVICES + permissions.

Device cgroup lacked /dev/nvidia1 → added DeviceAllow=/dev/nvidia1 rwm.

Enabled multi-GPU spread with OLLAMA_SCHED_SPREAD=true. (Off by default; makes Ollama use all visible adapters.) 
HOSTKEY — premium web services provider
GitHub

OpenWebUI / Nginx / Certbot

Duplicate nginx vhosts for the same hostname on :80 → “conflicting server name … ignored”.

ACME challenge got proxied to app → 404; fixed with explicit webroot location for /.well-known/acme-challenge. 
eff-certbot.readthedocs.io
certbot.eff.org

DuckDNS showed A/AAAA mismatch vs actual WAN IP; Let’s Encrypt was validating the wrong address.

Used DNS-01 with DuckDNS TXT API to issue a cert (no ports required). 
duckdns.org

nginx -t as non-root failed to read LE private key (expected; run with sudo).

Added deploy hook to reload nginx on renewal.

one-liners you’ll reuse
Expose + spread across both GPUs (systemd override):

ini
Copy
Edit
[Service]
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
Environment=CUDA_VISIBLE_DEVICES=0,1
Environment=OLLAMA_LLM_LIBRARY=cuda
Environment=OLLAMA_NO_CUDA=0
Environment=OLLAMA_NUM_GPU_LAYERS=999
Environment=OLLAMA_SCHED_SPREAD=true
DeviceAllow=/dev/nvidiactl rwm
DeviceAllow=/dev/nvidia-uvm rwm
DeviceAllow=/dev/nvidia0 rwm
DeviceAllow=/dev/nvidia1 rwm
nginx
Copy
Edit
sudo systemctl daemon-reload && sudo systemctl restart ollama
Check who owns 11434 (kill a stray Ollama):

bash
Copy
Edit
sudo ss -lptn 'sport = :11434'; sudo lsof -i :11434
pkill -f 'ollama serve' || true
DuckDNS update (A & clear AAAA):

bash
Copy
Edit
curl -fsS "https://www.duckdns.org/update?domains=ryleh-openweb,ryleh-forum&token=YOURTOKEN&ip="
curl -fsS "https://www.duckdns.org/update?domains=ryleh-openweb,ryleh-forum&token=YOURTOKEN&ipv6="

From start to finish, you successfully navigated a common but tricky deployment process:

Diagnosed Failure: You identified that the initial http-01 challenge was failing because your server is behind a NAT/CGNAT.

Changed Strategy: You correctly switched to the dns-01 challenge, which is the standard solution for this scenario.

Automated DNS: You implemented the duckdns-auth.sh and duckdns-clean.sh hook scripts to automate the DNS validation.

Solved Permissions: You fixed the final "Permission denied" error by using sudo to test and reload the Nginx configuration.
