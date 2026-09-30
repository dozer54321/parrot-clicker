#!/bin/bash
# Parrot Clicker — install Docker if needed, then sit beside the Caddy you already run.
# Usage: sudo ./install.sh parrots.yourmomon.top
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo so Docker can be installed. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  if [ -t 0 ] || [ -e /dev/tty ]; then
    read -r -p "Hostname (example: parrots.yourmomon.top): " DOMAIN < /dev/tty
  fi
fi
DOMAIN="$(echo "$DOMAIN" | tr -d '[:space:]')"
if [ -z "$DOMAIN" ]; then
  echo "Usage: sudo ./install.sh parrots.yourmomon.top"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  echo "Missing docker-compose.yml next to this installer."
  exit 1
fi
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git openssl python3 docker.io docker-compose-v2
systemctl enable --now docker

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
fi

chmod +x "$ROOT/deploy/vps/"*.sh 2>/dev/null || true

"$ROOT/deploy/vps/start.sh" "$DOMAIN"
