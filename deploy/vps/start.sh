#!/bin/bash
# Parrot Clicker — start next to an existing Caddy, or with our own Caddy container.
# Usage: ./start.sh parrot.yourmomon.top
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: ./start.sh parrot.yourmomon.top"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

CADDY_LIB=""
for f in "$ROOT/caddy.sh" "$ROOT/deploy/vps/caddy.sh"; do
  if [ -f "$f" ]; then CADDY_LIB="$f"; break; fi
done
if [ -z "$CADDY_LIB" ]; then
  echo "Missing caddy.sh"
  exit 1
fi
# shellcheck disable=SC1090
. "$CADDY_LIB"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. On Ubuntu, run:  sudo ./install.sh $DOMAIN"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running, or this user cannot talk to it."
  exit 1
fi

ENV_FILE="$ROOT/parrot.env"
if [ -f "$ENV_FILE" ]; then
  echo "Keeping existing parrot.env."
else
  umask 077
  cat > "$ENV_FILE" <<EOF
PARROT_DOMAIN=${DOMAIN}
PARROT_PORT=3060
PARROT_IMAGE=parrot:local
EOF
  echo "Wrote parrot.env."
fi

set_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

set_env PARROT_DOMAIN "$DOMAIN"
if ! grep -q '^PARROT_PORT=' "$ENV_FILE"; then
  set_env PARROT_PORT 3060
fi
if [ -f "$ROOT/VERSION" ]; then
  set_env PARROT_VERSION "$(tr -d '[:space:]' < "$ROOT/VERSION")"
fi

if [ -f "$ROOT/parrot-image.tar.gz" ]; then
  echo "Loading prebuilt Parrot Clicker image..."
  docker load -i "$ROOT/parrot-image.tar.gz"
fi

if docker image inspect parrot:local >/dev/null 2>&1; then
  VER="$(grep '^PARROT_VERSION=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
  if [ -n "$VER" ] && docker image inspect "parrot:${VER}" >/dev/null 2>&1; then
    set_env PARROT_IMAGE "parrot:${VER}"
  else
    set_env PARROT_IMAGE parrot:local
  fi
fi

compose_up() {
  local profiles=()
  if [ "${1:-}" = "edge" ]; then
    profiles=(--profile edge)
  fi
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
  local img
  img="$(grep '^PARROT_IMAGE=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
  if [ -z "$img" ]; then img="parrot:local"; fi
  if docker image inspect "$img" >/dev/null 2>&1 || docker image inspect parrot:local >/dev/null 2>&1; then
    docker compose "${profiles[@]}" --env-file "$ENV_FILE" up -d
  else
    echo "No image yet — building Parrot Clicker (this is the slow step)."
    docker compose "${profiles[@]}" --env-file "$ENV_FILE" up -d --build
  fi
}

wait_app() {
  local i
  local port="${PARROT_PORT:-3060}"
  echo "Waiting for Parrot Clicker on 127.0.0.1:${port}..."
  for i in $(seq 1 60); do
    if curl -sf --max-time 2 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
      echo "Parrot Clicker is up."
      return 0
    fi
    sleep 2
  done
  echo "Parrot Clicker did not answer. Last logs:"
  docker logs --tail 80 parrot-app 2>/dev/null || true
  return 1
}

parrot_detect_caddy

rm -f "$ROOT/docker-compose.override.yml"
if [ "$CADDY_KIND" = "docker" ] && [ -n "$CADDY_NET" ]; then
  parrot_write_net_override "$ROOT" "$CADDY_NET"
  echo "Will share Caddy's Docker network: $CADDY_NET"
fi

# shellcheck disable=SC1091
set -a
. "$ENV_FILE"
set +a

if [ "$CADDY_KIND" = "none" ]; then
  echo "No existing Caddy — starting Parrot Clicker with its own Caddy container."
  compose_up edge
  wait_app || true
else
  echo "Using existing Caddy (${CADDY_KIND}). Not binding :80 or :443."
  if ! compose_up; then
    echo "Compose with the shared network failed — starting on Parrot's network only."
    rm -f "$ROOT/docker-compose.override.yml"
    compose_up
  fi
  wait_app || true
  parrot_piggyback "$DOMAIN" || {
    echo "Could not piggyback. Check the Caddyfile and that ports 80/443 belong to the Caddy you already run."
    exit 1
  }
fi

echo
echo "Open https://${DOMAIN}"
echo "App container: parrot-app    localhost port: ${PARROT_PORT:-3060}"
echo
echo "Logs:   docker compose --env-file parrot.env logs -f app"
echo "Stop:   docker compose --env-file parrot.env down"
echo "Repair: sudo ./deploy/vps/repair.sh ${DOMAIN}"
if [ "$(id -u)" -eq 0 ]; then
  "$ROOT/deploy/vps/update.sh" --install-timer
else
  echo "Auto-update: sudo ./deploy/vps/update.sh --install-timer"
fi
