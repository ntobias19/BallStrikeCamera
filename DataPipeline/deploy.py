#!/usr/bin/env python3
"""Creates 10 DO droplets, deploys 18Birdies worker, starts scraping."""
import json, os, subprocess, sys, time

DO_KEY       = os.environ.get("DO_API_KEY", "")  # export DO_API_KEY=your_key
SSH_KEY_ID   = 56811740
DO_REGION    = "nyc3"
DO_SIZE      = "s-2vcpu-4gb"
DO_IMAGE     = "ubuntu-22-04-x64"
SUPABASE_URL = "https://aoxturoezgecwceudeef.supabase.co"
SERVICE_KEY  = open(os.path.expanduser(
    "~/Downloads/BallStrikeCamera/Config/service_role.key")).read().strip()
NUM_DROPLETS = 10
CHUNK_DIR    = "/tmp/birdies_chunks"
WORKER_SRC   = os.path.expanduser("~/Downloads/BallStrikeCamera/worker.py")


def do_curl(method, path, body=None):
    cmd = ["curl", "-s", "-X", method,
           f"https://api.digitalocean.com/v2{path}",
           "-H", f"Authorization: Bearer {DO_KEY}",
           "-H", "Content-Type: application/json"]
    if body:
        cmd += ["-d", json.dumps(body)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    try:
        return json.loads(r.stdout)
    except:
        print(f"  curl error: {r.stdout[:200]} {r.stderr[:100]}")
        return {}


def ssh(ip, cmd, timeout=180):
    return subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10",
         f"root@{ip}", cmd],
        capture_output=True, text=True, timeout=timeout)


def scp(ip, local, remote, timeout=60):
    return subprocess.run(
        ["scp", "-o", "StrictHostKeyChecking=no", local, f"root@{ip}:{remote}"],
        capture_output=True, text=True, timeout=timeout)


# ── 1. Create droplets ────────────────────────────────────────────────────────
BOOTSTRAP_CMD = """
export DEBIAN_FRONTEND=noninteractive && \
apt-get update -qq && \
apt-get install -y -qq python3-pip && \
pip3 install -q playwright requests rapidfuzz && \
python3 -m playwright install chromium && \
python3 -m playwright install-deps chromium && \
echo BOOTSTRAP_DONE > /tmp/bootstrap_done
"""

print("Creating 10 droplets...", flush=True)
droplet_ids = []
for i in range(NUM_DROPLETS):
    body = {
        "name": f"birdies-worker-{i}",
        "region": DO_REGION,
        "size": DO_SIZE,
        "image": DO_IMAGE,
        "ssh_keys": [SSH_KEY_ID],
        "tags": ["birdies-scraper"],
    }
    resp = do_curl("POST", "/v2/droplets", body)
    did = resp.get("droplet", {}).get("id")
    if did:
        print(f"  droplet {i}: id={did} ✓")
        droplet_ids.append(did)
    else:
        print(f"  droplet {i}: FAILED — {resp}")
        sys.exit(1)

# ── 2. Wait for IPs ───────────────────────────────────────────────────────────
print("\nWaiting for IPs...", flush=True)
ips = {}
while len(ips) < NUM_DROPLETS:
    time.sleep(10)
    for did in droplet_ids:
        if did in ips:
            continue
        resp = do_curl("GET", f"/v2/droplets/{did}")
        nets = resp.get("droplet", {}).get("networks", {}).get("v4", [])
        ip = next((n["ip_address"] for n in nets if n["type"] == "public"), None)
        if ip:
            ips[did] = ip
            print(f"  {did} → {ip} ✓")
    print(f"  {len(ips)}/{NUM_DROPLETS} have IPs", flush=True)

ip_list = [ips[did] for did in droplet_ids]
with open("/tmp/birdies_droplet_ips.txt", "w") as f:
    f.write("\n".join(ip_list))
print(f"IPs: {ip_list}")

# ── 3. Bootstrap via SSH (install playwright etc.) ───────────────────────────
print("\nBootstrapping droplets via SSH...", flush=True)
import threading

def bootstrap_droplet(ip):
    # Wait until SSH is reachable
    for _ in range(20):
        r = ssh(ip, "echo ok", timeout=15)
        if r.returncode == 0:
            break
        time.sleep(8)
    r = ssh(ip, BOOTSTRAP_CMD, timeout=300)
    return ip, r.returncode == 0

threads = []
results = {}
for ip in ip_list:
    t = threading.Thread(target=lambda ip=ip: results.update({ip: bootstrap_droplet(ip)[1]}))
    t.start()
    threads.append(t)
for t in threads:
    t.join()

for ip, ok in results.items():
    print(f"  {ip} bootstrap {'✓' if ok else 'FAILED'}")

bootstrapped = {ip for ip, ok in results.items() if ok}
if len(bootstrapped) < NUM_DROPLETS:
    print(f"WARNING: only {len(bootstrapped)}/{NUM_DROPLETS} bootstrapped — proceeding")

# ── 4. Deploy and start ───────────────────────────────────────────────────────
print("\nDeploying + starting workers...", flush=True)
for i, ip in enumerate(ip_list):
    scp(ip, WORKER_SRC, "/root/worker.py")
    scp(ip, f"{CHUNK_DIR}/courses_{i}.json", "/root/courses.json")
    start = (
        f"SUPABASE_URL='{SUPABASE_URL}' SERVICE_KEY='{SERVICE_KEY}' "
        f"nohup python3 /root/worker.py "
        f"--courses /root/courses.json "
        f"--supabase-url '{SUPABASE_URL}' "
        f"--service-key '{SERVICE_KEY}' "
        f"--results-file /root/results.jsonl "
        f"> /tmp/worker.log 2>&1 &"
    )
    r = ssh(ip, start)
    print(f"  {ip} worker {'started ✓' if r.returncode == 0 else 'FAILED: ' + r.stderr[:80]}")

# ── 5. Print monitoring command ───────────────────────────────────────────────
monitor_cmd = (
    "watch -n 15 'echo \"=== $(date) ===\"; "
    "for ip in $(cat /tmp/birdies_droplet_ips.txt); do "
    "echo \"--- $ip ---\"; "
    "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$ip "
    "\"tail -2 /tmp/worker.log 2>/dev/null\" ; done'"
)

print("\n" + "=" * 65)
print("ALL 10 WORKERS RUNNING — 25,365 courses across 10 droplets")
print("\nMonitor command (paste in your terminal):\n")
print(monitor_cmd)
print("\nOr tail one droplet live:")
print(f"  ssh root@{ip_list[0]} 'tail -f /tmp/worker.log'")
print("=" * 65)

with open("/tmp/birdies_monitor_cmd.sh", "w") as f:
    f.write(f"#!/bin/bash\n{monitor_cmd}\n")
os.chmod("/tmp/birdies_monitor_cmd.sh", 0o755)
