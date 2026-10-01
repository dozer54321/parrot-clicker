#!/bin/bash
# Same hook as Momon: find the Caddy already running, join its network,
# write one site block, reload that Caddy. Does not start another one.
#   sudo bash fix-tls.sh
set -euo pipefail

DOMAIN="${1:-parrot.yourmomon.top}"
if [ "$(id -u)" -ne 0 ]; then
  exec sudo -E "$0" "$@"
fi

parrot_docker_caddy_id() {
  docker ps --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null \
    | grep -i caddy \
    | grep -vi parrot-caddy \
    | awk '{print $1}' \
    | head -1
}

parrot_caddyfile_from_container() {
  local id="$1"
  local dest src
  while read -r dest src; do
    [ -n "$dest" ] || continue
    case "$dest" in
      /etc/caddy/Caddyfile)
        if [ -f "$src" ]; then echo "$src"; return 0; fi
        ;;
      /etc/caddy)
        if [ -f "$src/Caddyfile" ]; then echo "$src/Caddyfile"; return 0; fi
        ;;
    esac
    case "$src" in
      *Caddyfile)
        if [ -f "$src" ]; then echo "$src"; return 0; fi
        ;;
    esac
  done < <(docker inspect -f '{{range .Mounts}}{{.Destination}} {{.Source}}{{"\n"}}{{end}}' "$id" 2>/dev/null)
  for f in /opt/requestick/Caddyfile /opt/caddy/Caddyfile /etc/caddy/Caddyfile; do
    if [ -f "$f" ]; then echo "$f"; return 0; fi
  done
  return 1
}

parrot_caddy_net() {
  local id="$1"
  docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' "$id" 2>/dev/null \
    | awk 'NF && $0 != "bridge" && $0 != "host" && $0 != "none" {print; exit}'
}

parrot_detect_caddy() {
  CADDY_KIND=none
  CADDY_FILE=""
  CADDY_ID=""
  CADDY_NET=""

  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet caddy 2>/dev/null; then
    CADDY_KIND=host
    for f in /etc/caddy/Caddyfile /usr/local/etc/caddy/Caddyfile; do
      if [ -f "$f" ]; then CADDY_FILE="$f"; break; fi
    done
    [ -n "$CADDY_FILE" ] || CADDY_FILE=/etc/caddy/Caddyfile
    echo "Found host Caddy (systemd) → $CADDY_FILE"
    return 0
  fi

  if command -v caddy >/dev/null 2>&1 && pgrep -x caddy >/dev/null 2>&1; then
    CADDY_KIND=host
    for f in /etc/caddy/Caddyfile /usr/local/etc/caddy/Caddyfile; do
      if [ -f "$f" ]; then CADDY_FILE="$f"; break; fi
    done
    [ -n "$CADDY_FILE" ] || CADDY_FILE=/etc/caddy/Caddyfile
    echo "Found host Caddy (process) → $CADDY_FILE"
    return 0
  fi

  CADDY_ID="$(parrot_docker_caddy_id || true)"
  if [ -n "$CADDY_ID" ]; then
    CADDY_KIND=docker
    CADDY_NET="$(parrot_caddy_net "$CADDY_ID" || true)"
    CADDY_FILE="$(parrot_caddyfile_from_container "$CADDY_ID" || true)"
    echo "Found Caddy container ${CADDY_ID:0:12} net=${CADDY_NET:-?} file=${CADDY_FILE:-unset}"
    return 0
  fi

  echo "No Caddy on the host or in Docker."
  return 0
}

parrot_write_site() {
  local caddyfile="$1"
  local domain="$2"
  local target="$3"
  if [ -z "$caddyfile" ]; then
    echo "No Caddyfile path — cannot add ${domain}."
    return 1
  fi
  mkdir -p "$(dirname "$caddyfile")"
  python3 - "$caddyfile" "$domain" "$target" <<'PY'
import pathlib, re, socket, sys
path = pathlib.Path(sys.argv[1])
domain = sys.argv[2]
target = sys.argv[3]
www = f"www.{domain}"
try:
    socket.getaddrinfo(www, 443)
    addr = f"{domain}, {www}"
except OSError:
    addr = domain
block = (
    f"{addr} {{\n"
    f"  encode gzip\n"
    f"  reverse_proxy {target}\n"
    f"}}\n"
)
text = path.read_text() if path.exists() else ""
text = re.sub(r"(?ms)^# begin-parrot\n.*?# end-parrot\n?", "", text)
alts = "|".join(re.escape(n) for n in (domain, www, "parrots.yourmomon.top", "www.parrots.yourmomon.top"))
pattern = re.compile(rf"(?m)^(?:{alts})(?:,[^\n]*)?\s*\{{[\s\S]*?^\}}\s*")
text, _ = pattern.subn("", text)
path.write_text(text.rstrip() + "\n\n" + block)
print(f"Caddy: {addr} → {target}")
PY
}

parrot_reload_caddy() {
  case "${CADDY_KIND}" in
    host)
      if command -v systemctl >/dev/null 2>&1; then
        systemctl reload caddy 2>/dev/null || systemctl restart caddy
      else
        caddy reload --config "$CADDY_FILE"
      fi
      ;;
    docker)
      if [ -n "$CADDY_ID" ]; then
        docker exec "$CADDY_ID" caddy reload --config /etc/caddy/Caddyfile 2>/dev/null \
          || docker restart "$CADDY_ID"
      fi
      ;;
  esac
}

parrot_join_caddy_net() {
  local i
  [ -n "${CADDY_NET:-}" ] || return 0
  for i in $(seq 1 30); do
    if docker inspect -f '{{.State.Running}}' parrot-app 2>/dev/null | grep -qx true; then
      docker network connect "$CADDY_NET" parrot-app 2>/dev/null || true
      return 0
    fi
    sleep 2
  done
}

parrot_piggyback() {
  local domain="$1"
  local port="${PARROT_PORT:-3060}"
  local target ip

  if [ "$CADDY_KIND" = "host" ]; then
    target="127.0.0.1:${port}"
    parrot_write_site "$CADDY_FILE" "$domain" "$target"
    parrot_reload_caddy
    echo "Piggybacked host Caddy."
    return 0
  fi

  if [ "$CADDY_KIND" = "docker" ]; then
    parrot_join_caddy_net
    target="parrot-app:3000"
    if [ -n "$CADDY_NET" ]; then
      ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${CADDY_NET}\").IPAddress}}" parrot-app 2>/dev/null || true)"
      if [ -n "$ip" ]; then
        target="${ip}:3000"
      fi
    fi
    if [ -z "$CADDY_FILE" ]; then
      echo "Caddy is a container but its Caddyfile is not on disk. Cannot piggyback."
      return 1
    fi
    parrot_write_site "$CADDY_FILE" "$domain" "$target"
    parrot_reload_caddy
    echo "Piggybacked Caddy container → ${target}"
    return 0
  fi

  return 1
}

if ! docker inspect parrot-app >/dev/null 2>&1; then
  if [ -f /opt/parrot-clicker/docker-compose.yml ] && [ -f /opt/parrot-clicker/parrot.env ]; then
    docker compose -f /opt/parrot-clicker/docker-compose.yml --env-file /opt/parrot-clicker/parrot.env up -d
  else
    echo "parrot-app is not running."
    exit 1
  fi
fi

parrot_detect_caddy
if [ "$CADDY_KIND" = "none" ]; then
  echo "No existing Caddy. Momon piggybacks on the one already installed."
  exit 1
fi

parrot_piggyback "$DOMAIN"
echo "Open https://${DOMAIN}"
