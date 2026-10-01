#!/bin/bash
# Make Caddy serve a real certificate for parrot.yourmomon.top.
# The broken handshake is "no certificate for this exact name": the live
# block was missing, still said "parrots", or still included www (no DNS).
#   sudo bash fix-tls.sh
set -euo pipefail

DOMAIN="${1:-parrot.yourmomon.top}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo to edit Caddy. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

rewrite() {
  local file="$1"
  local target="$2"
  python3 - "$file" "$DOMAIN" "$target" <<'PY'
import pathlib, sys
path, domain, target = sys.argv[1:]
file = pathlib.Path(path)
text = file.read_text(errors="replace") if file.exists() else ""
names = {
    domain,
    f"www.{domain}",
    "parrots.yourmomon.top",
    "www.parrots.yourmomon.top",
}
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
file.parent.mkdir(parents=True, exist_ok=True)
file.write_text("".join(out).rstrip() + "\n" + block)
print(f"Wrote {domain} → {target} in {file}")
PY
}

caddy_ids() {
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null \
    | grep -i caddy \
    | grep -vi parrot-caddy \
    | awk '{print $1}' \
    || true
}

# Put the app on Caddy's network so the name parrot-app resolves at reload.
if docker inspect parrot-app >/dev/null 2>&1; then
  for cid in $(caddy_ids); do
    docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$cid" 2>/dev/null \
      | while read -r net; do
          [ -n "$net" ] || continue
          case "$net" in bridge|host|none) continue ;; esac
          docker network connect --alias parrot-app "$net" parrot-app 2>/dev/null || true
          echo "Joined parrot-app to ${net}."
        done
  done
fi

declare -a FILES=()
declare -a TARGETS=()

add_job() {
  local file="$1"
  local target="$2"
  [ -n "$file" ] || return 0
  local i
  for i in "${!FILES[@]}"; do
    if [ "${FILES[$i]}" = "$file" ]; then
      return 0
    fi
  done
  FILES+=("$file")
  TARGETS+=("$target")
}

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy 2>/dev/null; then
  host_file=""
  for f in /etc/caddy/Caddyfile /usr/local/etc/caddy/Caddyfile; do
    if [ -f "$f" ]; then
      host_file="$f"
      break
    fi
  done
  [ -n "$host_file" ] || host_file=/etc/caddy/Caddyfile
  add_job "$host_file" "127.0.0.1:${PARROT_PORT:-3060}"
fi

for cid in $(caddy_ids); do
  while read -r dest src; do
    [ -n "$dest" ] || continue
    case "$dest" in
      /etc/caddy/Caddyfile)
        [ -f "$src" ] && add_job "$src" "parrot-app:3000"
        ;;
      /etc/caddy)
        [ -f "$src/Caddyfile" ] && add_job "$src/Caddyfile" "parrot-app:3000"
        ;;
    esac
  done < <(docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Source}}{{"\n"}}{{end}}' "$cid" 2>/dev/null)
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "Could not find the Caddyfile Caddy is actually using."
  echo "Host service:"
  systemctl status caddy --no-pager 2>/dev/null | head -20 || true
  echo "Containers:"
  docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null || true
  exit 1
fi

for i in "${!FILES[@]}"; do
  rewrite "${FILES[$i]}" "${TARGETS[$i]}"
done

reloaded=0
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy 2>/dev/null; then
  echo "Reloading host Caddy..."
  systemctl reload caddy
  reloaded=1
fi
for cid in $(caddy_ids); do
  echo "Reloading Caddy container ${cid:0:12}..."
  if docker exec "$cid" caddy reload --config /etc/caddy/Caddyfile; then
    reloaded=1
  else
    echo "Reload failed. Caddy kept the previous config, so the certificate was not requested."
    docker logs --tail 40 "$cid" 2>&1 || true
    exit 1
  fi
done

if [ "$reloaded" -ne 1 ]; then
  echo "Nothing reloaded."
  exit 1
fi

echo "Waiting for a certificate for https://${DOMAIN}/ ..."
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

echo "Caddy reloaded, but https://${DOMAIN}/ still has no working certificate."
echo "Recent Caddy log:"
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy 2>/dev/null; then
  journalctl -u caddy -n 50 --no-pager || true
fi
for cid in $(caddy_ids); do
  docker logs --tail 50 "$cid" 2>&1 || true
done
exit 1
