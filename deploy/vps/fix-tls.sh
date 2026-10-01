#!/bin/bash
# Add parrot.yourmomon.top to Requestick's Caddy — the one already on port 443.
# Does not start a second Caddy and does not include www (that name has no DNS).
#   sudo bash fix-tls.sh
set -euo pipefail

DOMAIN="${1:-parrot.yourmomon.top}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo to edit Requestick's Caddy. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed, so Requestick's Caddy container is not here."
  exit 1
fi

# Whoever publishes 443 is Requestick's Caddy (mesh-caddy).
CID="$(docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' | awk '/443->/ {print $1; exit}')"
if [ -z "$CID" ]; then
  CID="$(docker ps --format '{{.ID}} {{.Names}}' | awk 'BEGIN{IGNORECASE=1} /mesh-caddy/ {print $1; exit}')"
fi
if [ -z "$CID" ]; then
  echo "No container is listening on port 443. Requestick's Caddy is not running."
  docker ps --format '{{.Names}} {{.Ports}}' || true
  exit 1
fi
CNAME="$(docker ps --format '{{.Names}}' --filter "id=${CID}" | head -1)"
echo "Port 443 is ${CNAME}. Editing that Caddyfile."

FILE=""
while read -r dest src; do
  [ -n "$dest" ] || continue
  case "$dest" in
    /etc/caddy/Caddyfile)
      [ -f "$src" ] && FILE="$src"
      ;;
    /etc/caddy)
      [ -f "$src/Caddyfile" ] && FILE="$src/Caddyfile"
      ;;
  esac
done < <(docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Source}}{{"\n"}}{{end}}' "$CID")
if [ -z "$FILE" ] && [ -f /opt/requestick/Caddyfile ]; then
  FILE=/opt/requestick/Caddyfile
fi
if [ -z "$FILE" ]; then
  echo "Could not find the Caddyfile mounted into ${CNAME}."
  docker inspect -f '{{range .Mounts}}{{.Destination}} <- {{.Source}}{{"\n"}}{{end}}' "$CID"
  exit 1
fi
echo "Requestick Caddyfile: ${FILE}"

if ! docker inspect parrot-app >/dev/null 2>&1; then
  if [ -f /opt/parrot-clicker/docker-compose.yml ] && [ -f /opt/parrot-clicker/parrot.env ]; then
    echo "Starting parrot-app."
    docker compose -f /opt/parrot-clicker/docker-compose.yml --env-file /opt/parrot-clicker/parrot.env up -d
  else
    echo "parrot-app is not running and /opt/parrot-clicker is missing."
    exit 1
  fi
fi

NETS="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$CID")"
TARGET=""
while read -r net; do
  [ -n "$net" ] || continue
  case "$net" in bridge|host|none) continue ;; esac
  docker network connect --alias parrot-app "$net" parrot-app 2>/dev/null || true
  ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${net}\").IPAddress}}" parrot-app 2>/dev/null || true)"
  if [ -n "$ip" ]; then
    TARGET="${ip}:3000"
    echo "parrot-app is on Requestick's network ${net} at ${ip}."
    break
  fi
done <<<"$NETS"

if [ -z "$TARGET" ]; then
  echo "Could not attach parrot-app to Requestick's network."
  echo "$NETS"
  exit 1
fi

python3 - "$FILE" "$DOMAIN" "$TARGET" <<'PY'
import pathlib, sys
path, domain, target = sys.argv[1:]
file = pathlib.Path(path)
text = file.read_text(errors="replace") if file.exists() else ""
names = {domain, f"www.{domain}", "parrots.yourmomon.top", "www.parrots.yourmomon.top"}
lines = text.splitlines(keepends=True)
out = []
i = 0
while i < len(lines):
    stripped = lines[i].strip()
    if stripped == "# begin-parrot":
        i += 1
        while i < len(lines) and lines[i].strip() != "# end-parrot":
            i += 1
        if i < len(lines):
            i += 1
        continue
    head = stripped.split("{", 1)[0]
    hosts = [h.strip() for h in head.split(",") if h.strip()]
    if "{" in stripped and any(h in names for h in hosts):
        depth = stripped.count("{") - stripped.count("}")
        i += 1
        while i < len(lines) and depth > 0:
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
        continue
    out.append(lines[i])
    i += 1
block = (
    "\n# begin-parrot\n"
    f"{domain} {{\n"
    "\tencode gzip\n"
    f"\treverse_proxy {target}\n"
    "}\n"
    "# end-parrot\n"
)
file.write_text("".join(out).rstrip() + "\n" + block)
print(f"Added {domain} → {target}")
PY

echo "Checking Requestick's Caddyfile..."
if ! docker exec "$CID" caddy validate --config /etc/caddy/Caddyfile; then
  echo "Requestick refused the Caddyfile. Nothing was reloaded, so the other sites stay up."
  exit 1
fi

echo "Reloading ${CNAME}..."
if ! docker exec "$CID" caddy reload --config /etc/caddy/Caddyfile; then
  echo "Reload failed. Recent logs:"
  docker logs --tail 40 "$CID" || true
  exit 1
fi

echo "Waiting for a certificate..."
ok=0
for _ in $(seq 1 20); do
  if curl -fsS -o /dev/null --max-time 8 "https://${DOMAIN}/"; then
    ok=1
    break
  fi
  sleep 3
done
if [ "$ok" -eq 1 ]; then
  echo "HTTPS is up: https://${DOMAIN}/"
  exit 0
fi

echo "Reloaded Requestick, but https://${DOMAIN}/ still has no certificate."
docker logs --tail 60 "$CID" || true
exit 1
