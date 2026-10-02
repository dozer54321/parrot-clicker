#!/bin/bash
# Parrot joined the shared Caddy network as "app" and stole every site that
# proxies to app:3000 (Requestick, Take-Home, and anything else written that way).
# Put parrot back under the name parrot-app only. Do not restart Caddy.
#   sudo bash unbreak-caddy.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E "$0" "$@"
fi

if ! docker inspect parrot-app >/dev/null 2>&1; then
  echo "parrot-app is not running. Nothing to detach."
  exit 1
fi

echo "Taking the name \"app\" away from parrot-app."
while read -r net; do
  [ -n "$net" ] || continue
  case "$net" in
    parrot|parrot_parrot|*_parrot) continue ;;
  esac
  echo "Reconnecting on ${net} as parrot-app only."
  docker network disconnect "$net" parrot-app 2>/dev/null || true
  docker network connect --alias parrot-app "$net" parrot-app
done < <(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' parrot-app)

# Keep the next compose recreate from registering "app" again.
python3 - <<'PY'
from pathlib import Path
root = Path("/opt/parrot-clicker")
compose = root / "docker-compose.yml"
if compose.is_file() and "parrot-app" in compose.read_text():
    text = compose.read_text()
    text = text.replace("\n  app:\n", "\n  parrot:\n", 1)
    text = text.replace("\n      - app\n", "\n      - parrot\n")
    compose.write_text(text)
    print(f"Updated {compose}")
override = root / "docker-compose.override.yml"
if override.is_file():
    text = override.read_text().replace("\n  app:\n", "\n  parrot:\n")
    override.write_text(text)
    print(f"Updated {override}")
updater = root / "deploy/vps/update.sh"
if updater.is_file():
    text = updater.read_text().replace("--force-recreate app", "--force-recreate parrot")
    updater.write_text(text)
PY

# If the parrot site was pinned to the stolen name, point that one block at parrot-app.
cid="$(docker ps --format '{{.ID}} {{.Ports}}' | awk '/443->/ {print $1; exit}')"
file=""
if [ -n "$cid" ]; then
  while read -r dest src; do
    case "$dest" in
      /etc/caddy/Caddyfile) [ -f "$src" ] && file="$src" ;;
      /etc/caddy) [ -f "$src/Caddyfile" ] && file="$src/Caddyfile" ;;
    esac
  done < <(docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Source}}{{"\n"}}{{end}}' "$cid")
fi
if [ -n "$file" ]; then
  python3 - "$file" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
lines = path.read_text(errors="replace").splitlines(keepends=True)
names = {"parrot.yourmomon.top", "www.parrot.yourmomon.top", "parrots.yourmomon.top", "www.parrots.yourmomon.top"}
out = []
i = 0
changed = False
while i < len(lines):
    stripped = lines[i].strip()
    head = stripped.split("{", 1)[0]
    hosts = [h.strip() for h in head.split(",") if h.strip()]
    if "{" in stripped and any(h in names for h in hosts):
        depth = stripped.count("{") - stripped.count("}")
        block = [lines[i]]
        i += 1
        while i < len(lines) and depth > 0:
            depth += lines[i].count("{") - lines[i].count("}")
            block.append(lines[i])
            i += 1
        text = "".join(block)
        new = text.replace("reverse_proxy app:3000", "reverse_proxy parrot-app:3000")
        if new != text:
            changed = True
        out.append(new)
        continue
    out.append(lines[i])
    i += 1
if changed:
    path.write_text("".join(out))
    print(f"Pointed the parrot site at parrot-app in {path}")
else:
    print("Left every other site block alone.")
PY
  if docker exec "$cid" caddy validate --config /etc/caddy/Caddyfile; then
    docker exec "$cid" caddy reload --config /etc/caddy/Caddyfile || true
  else
    echo "Did not reload Caddy. The other sites stay on the config already loaded."
  fi
  echo "Who answers http://app:3000/ inside Caddy:"
  docker exec "$cid" wget -qO- --timeout=4 http://app:3000/ 2>/dev/null | head -c 180 || echo "(no answer)"
  echo
fi

echo "Done. Other apps should be themselves again. Parrot stays on https://parrot.yourmomon.top"
