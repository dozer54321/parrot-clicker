#!/bin/bash
# The live site is a blank 502: Caddy has the certificate, but it cannot reach
# the app. This puts parrot-app on that Caddy's network and repoints the site.
#   sudo bash fix-upstream.sh
set -euo pipefail

DOMAIN="${1:-parrot.yourmomon.top}"
if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E "$0" "$@"
fi

echo "Blank page is a 502. Connecting the app to the Caddy that has the certificate."

if ! docker inspect parrot-app >/dev/null 2>&1; then
  if [ -f /opt/parrot-clicker/docker-compose.yml ]; then
    echo "parrot-app is missing. Starting it."
    if docker image inspect parrot:local >/dev/null 2>&1; then
      docker compose -f /opt/parrot-clicker/docker-compose.yml --env-file /opt/parrot-clicker/parrot.env up -d
    else
      docker compose -f /opt/parrot-clicker/docker-compose.yml --env-file /opt/parrot-clicker/parrot.env up -d --build
    fi
  else
    echo "parrot-app is not installed. Run the installer:"
    echo "  curl -fsSL -o /tmp/parrot-install.sh https://raw.githubusercontent.com/dozer54321/parrot-clicker/main/deploy/vps/bootstrap.sh"
    echo "  sudo bash /tmp/parrot-install.sh"
    exit 1
  fi
fi

state="$(docker inspect -f '{{.State.Status}}' parrot-app)"
if [ "$state" != "running" ]; then
  echo "parrot-app is ${state}. Starting it."
  docker start parrot-app >/dev/null
fi

echo "Waiting for the app inside the container..."
ready=0
for _ in $(seq 1 30); do
  if docker exec parrot-app node -e "fetch('http://127.0.0.1:3000/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if [ "$ready" != 1 ]; then
  echo "The app container is running but not answering on port 3000."
  docker logs --tail 80 parrot-app || true
  exit 1
fi
echo "App is answering inside parrot-app."

CID="$(docker ps --format '{{.ID}} {{.Ports}}' | awk '/443->/ {print $1; exit}')"
if [ -z "$CID" ]; then
  CID="$(docker ps --format '{{.ID}} {{.Names}}' | grep -i caddy | grep -vi parrot-caddy | awk '{print $1; exit}')"
fi
if [ -z "$CID" ]; then
  echo "No Caddy container is listening on 443."
  docker ps --format '{{.Names}} {{.Ports}}'
  exit 1
fi
CNAME="$(docker inspect -f '{{.Name}}' "$CID" | sed 's#^/##')"
echo "Caddy container: ${CNAME}"

FILE=""
while read -r dest src; do
  [ -n "${dest:-}" ] || continue
  case "$dest" in
    /etc/caddy/Caddyfile) [ -f "$src" ] && FILE="$src" ;;
    /etc/caddy) [ -f "$src/Caddyfile" ] && FILE="$src/Caddyfile" ;;
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
echo "Caddyfile: ${FILE}"

TARGET=""
while read -r net; do
  [ -n "$net" ] || continue
  case "$net" in bridge|host|none) continue ;; esac
  # Drop any "app" alias first. Other sites proxy to app:3000.
  docker network disconnect "$net" parrot-app 2>/dev/null || true
  docker network connect --alias parrot-app "$net" parrot-app 2>/dev/null || true
  sleep 1
  if docker exec "$CID" wget -q -O /dev/null --timeout=4 "http://parrot-app:3000/" 2>/dev/null; then
    TARGET="parrot-app:3000"
    echo "Caddy can reach http://parrot-app:3000/ on ${net}."
    break
  fi
  ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${net}\").IPAddress}}" parrot-app 2>/dev/null || true)"
  if [ -n "$ip" ] && docker exec "$CID" wget -q -O /dev/null --timeout=4 "http://${ip}:3000/" 2>/dev/null; then
    TARGET="${ip}:3000"
    echo "Caddy can reach http://${ip}:3000/ on ${net}."
    break
  fi
done < <(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$CID")

if [ -z "$TARGET" ]; then
  echo "Joined the networks, but Caddy still cannot open the app."
  docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{$v.IPAddress}}{{"\n"}}{{end}}' parrot-app || true
  exit 1
fi

python3 - "$FILE" "$DOMAIN" "$TARGET" <<'PY'
import pathlib, re, sys
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
    f"\n{domain} {{\n"
    f"  encode gzip\n"
    f"  reverse_proxy {target}\n"
    f"}}\n"
)
file.write_text("".join(out).rstrip() + "\n" + block)
print(f"Site {domain} → {target}")
PY

docker exec "$CID" caddy validate --config /etc/caddy/Caddyfile
docker exec "$CID" caddy reload --config /etc/caddy/Caddyfile \
  || docker restart "$CID"

echo "Waiting for https://${DOMAIN}/ ..."
for _ in $(seq 1 20); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "https://${DOMAIN}/" || true)"
  echo "  HTTP ${code:-none}"
  if [ "$code" = "200" ]; then
    echo "Live: https://${DOMAIN}/"
    exit 0
  fi
  sleep 2
done

echo "Still not 200. Caddy log:"
docker logs --tail 40 "$CID" || true
exit 1
