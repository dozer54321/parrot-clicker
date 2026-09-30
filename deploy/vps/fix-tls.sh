#!/bin/bash
# Drop www from the Parrot site block when that name has no DNS, then reload Caddy.
# A certificate that includes a name with no DNS never issues, and HTTPS dies
# with "Secure connection failed" even though port 80 redirects.
#   sudo bash deploy/vps/fix-tls.sh
set -euo pipefail

DOMAIN="${1:-parrot.yourmomon.top}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo to edit the Caddyfile. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

python3 - "$DOMAIN" <<'PY'
import os, pathlib, re, socket, subprocess, sys
domain = sys.argv[1]
www = f"www.{domain}"

def resolves(host):
    try:
        socket.getaddrinfo(host, 443)
        return True
    except OSError:
        return False

keep_www = resolves(www)
addr = domain if not keep_www else f"{domain}, {www}"
print(f"Certificate names: {addr}")

def rewrite(path: pathlib.Path) -> bool:
    if not path.is_file():
        return False
    text = path.read_text(errors="replace")
    if "begin-parrot" not in text and domain not in text and "parrots.yourmomon.top" not in text:
        return False
    pat = re.compile(r"(?ms)^# begin-parrot\n.*?# end-parrot\n?")
    m = pat.search(text)
    if not m:
        print(f"No parrot block in {path}")
        return False
    block = m.group(0)
    lines = block.splitlines()
    replaced = False
    for i, line in enumerate(lines):
        if line.startswith("#") or "{" not in line:
            continue
        lines[i] = f"{addr} {{"
        replaced = True
        break
    if not replaced:
        print(f"Could not find the site line in {path}")
        return False
    new = "\n".join(lines)
    if not new.endswith("\n"):
        new += "\n"
    if new == block:
        print(f"Already fine: {path}")
        return True
    path.write_text(text[: m.start()] + new + text[m.end() :])
    print(f"Updated {path}")
    return True

files = []
for candidate in (
    "/etc/caddy/Caddyfile",
    "/usr/local/etc/caddy/Caddyfile",
    "/opt/requestick/Caddyfile",
    "/opt/caddy/Caddyfile",
    "/opt/parrot-clicker/Caddyfile",
):
    files.append(pathlib.Path(candidate))

def docker_ids():
    try:
        out = subprocess.check_output(
            ["docker", "ps", "--format", "{{.ID}} {{.Image}} {{.Names}}"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return []
    ids = []
    for line in out.splitlines():
        if re.search(r"caddy", line, re.I) and "parrot-caddy" not in line.lower():
            ids.append(line.split()[0])
    return ids

for cid in docker_ids():
    try:
        mounts = subprocess.check_output(
            ["docker", "inspect", "-f", "{{range .Mounts}}{{.Destination}} {{.Source}}\n{{end}}", cid],
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        continue
    for line in mounts.splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        dest, src = parts
        if dest == "/etc/caddy/Caddyfile":
            files.append(pathlib.Path(src))
        elif dest == "/etc/caddy":
            files.append(pathlib.Path(src) / "Caddyfile")

changed = False
seen = set()
for path in files:
    key = str(path)
    if key in seen:
        continue
    seen.add(key)
    if rewrite(path):
        changed = True

if not changed:
    print("No Parrot block found. Looked in /etc/caddy and Caddy container mounts.")
    sys.exit(1)

reloaded = False
if os.path.exists("/run/systemd/system") or True:
    r = subprocess.run(["systemctl", "reload", "caddy"], capture_output=True, text=True)
    if r.returncode == 0:
        print("Reloaded host Caddy.")
        reloaded = True
for cid in docker_ids():
    r = subprocess.run(
        ["docker", "exec", cid, "caddy", "reload", "--config", "/etc/caddy/Caddyfile"],
        capture_output=True,
        text=True,
    )
    if r.returncode == 0:
        print(f"Reloaded Caddy container {cid[:12]}.")
        reloaded = True
    else:
        print(f"Reload failed in {cid[:12]}: {(r.stderr or r.stdout).strip()}")

if not reloaded:
    print("Edited the file but could not reload Caddy. Reload it, then open the site again.")
    sys.exit(1)
print("Caddy reloaded. HTTPS can take half a minute while the certificate is issued.")
PY
