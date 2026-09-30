#!/bin/bash
# Parrot Clicker keeps the flock in each browser (localStorage), not on the server.
# This only snapshots the compose env so a reinstall keeps the hostname and port.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

mkdir -p "$ROOT/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ -f "$ROOT/parrot.env" ]; then
  cp "$ROOT/parrot.env" "$ROOT/backups/parrot.env.$STAMP"
  echo "Copied parrot.env to backups/parrot.env.$STAMP"
else
  echo "No parrot.env yet. Nothing server-side to back up."
fi
echo "Player flocks live in the browser. They are not in Docker volumes."
