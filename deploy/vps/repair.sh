#!/bin/bash
# Re-attach Parrot Clicker to the Caddy already on this machine.
# Usage: sudo ./repair.sh parrots.yourmomon.top
set -euo pipefail

DOMAIN="${1:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

if [ -z "$DOMAIN" ] && [ -f "$ROOT/parrot.env" ]; then
  DOMAIN="$(grep '^PARROT_DOMAIN=' "$ROOT/parrot.env" | head -1 | cut -d= -f2-)"
fi
if [ -z "$DOMAIN" ]; then
  echo "Usage: sudo ./repair.sh parrots.yourmomon.top"
  exit 1
fi

# shellcheck disable=SC1091
. "$ROOT/deploy/vps/caddy.sh"
if [ -f "$ROOT/parrot.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$ROOT/parrot.env"
  set +a
fi

parrot_detect_caddy
if [ "$CADDY_KIND" = "none" ]; then
  echo "No existing Caddy found. Start with its own edge profile instead:"
  echo "  docker compose --env-file parrot.env --profile edge up -d"
  exit 1
fi

if [ "$CADDY_KIND" = "docker" ] && [ -n "$CADDY_NET" ]; then
  parrot_write_net_override "$ROOT" "$CADDY_NET"
  docker compose --env-file parrot.env up -d
fi

parrot_piggyback "$DOMAIN"
echo "Repaired ${DOMAIN} on the existing Caddy."
