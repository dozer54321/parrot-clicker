#!/bin/bash
# Detect an existing Caddy (host service or Docker container) and piggyback
# Parrot Clicker onto it. Sourced by start.sh / repair.sh — do not exec this file.
# Same idea as Momon and Take-Home: never steal :80/:443 from Requestick.

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

# Sets CADDY_KIND=host|docker|none, plus CADDY_FILE / CADDY_ID / CADDY_NET.
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
  if [ ! -w "$caddyfile" ] && [ ! -w "$(dirname "$caddyfile")" ]; then
    echo "Cannot write ${caddyfile}. Re-run with sudo."
    return 1
  fi
  mkdir -p "$(dirname "$caddyfile")"
  if command -v python3 >/dev/null 2>&1; then
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
    # Momon includes www because www.yourmomon.top exists. This name does not.
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
    return
  fi
  local addr="$domain"
  if getent hosts "www.${domain}" >/dev/null 2>&1; then
    addr="${domain}, www.${domain}"
  fi
  cat >> "$caddyfile" <<EOF

# begin-parrot
${addr} {
	encode gzip
	reverse_proxy ${target}
}
# end-parrot
EOF
  echo "Caddy: ${addr} → ${target}"
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

parrot_write_net_override() {
  local root="$1"
  local net="$2"
  cat > "$root/docker-compose.override.yml" <<EOF
# Generated: attach parrot-app to the existing Caddy network.
services:
  app:
    container_name: parrot-app
    networks:
      - parrot
      - caddy_net
networks:
  caddy_net:
    external: true
    name: ${net}
EOF
}

# Host Caddy talks to 127.0.0.1:3060. Docker Caddy talks to the app on the
# shared network, but only after that address answers. A dead IP is a 502.
parrot_pick_upstream() {
  local port="${PARROT_PORT:-3060}"
  local ip

  if [ "$CADDY_KIND" = "host" ]; then
    if curl -sf --max-time 3 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
      printf '%s\n' "127.0.0.1:${port}"
      return 0
    fi
    echo "Nothing is answering on 127.0.0.1:${port}." >&2
    return 1
  fi

  parrot_join_caddy_net
  sleep 1

  if [ -n "${CADDY_ID:-}" ] && docker exec "$CADDY_ID" wget -q -O /dev/null --timeout=4 "http://parrot-app:3000/" 2>/dev/null; then
    printf '%s\n' "parrot-app:3000"
    return 0
  fi

  ip=""
  if [ -n "${CADDY_NET:-}" ]; then
    ip="$(docker inspect -f "{{(index .NetworkSettings.Networks \"${CADDY_NET}\").IPAddress}}" parrot-app 2>/dev/null || true)"
  fi
  if [ -n "$ip" ]; then
    if [ -n "${CADDY_ID:-}" ] && docker exec "$CADDY_ID" wget -q -O /dev/null --timeout=4 "http://${ip}:3000/" 2>/dev/null; then
      printf '%s\n' "${ip}:3000"
      return 0
    fi
    if python3 -c "import socket; socket.create_connection(('${ip}', 3000), 3).close()" 2>/dev/null; then
      printf '%s\n' "${ip}:3000"
      return 0
    fi
  fi

  echo "Caddy cannot reach parrot-app." >&2
  docker ps -a --filter name=parrot-app --format '{{.Names}} {{.Status}}' >&2 || true
  docker logs --tail 60 parrot-app >&2 || true
  return 1
}

parrot_piggyback() {
  local domain="$1"
  local target

  target="$(parrot_pick_upstream)" || return 1
  if [ -z "$CADDY_FILE" ]; then
    echo "Caddy is running but its Caddyfile is not on disk. Cannot piggyback."
    return 1
  fi
  parrot_write_site "$CADDY_FILE" "$domain" "$target"
  parrot_reload_caddy
  echo "Piggybacked ${CADDY_KIND} Caddy → ${target}"
}
