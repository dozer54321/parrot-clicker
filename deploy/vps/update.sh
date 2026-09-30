#!/bin/bash
# Follow GitHub. When origin/main moves, reset to it and rebuild the container.
#   ./deploy/vps/update.sh                 # check once (timer runs this)
#   sudo ./deploy/vps/update.sh --install-timer
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

BRANCH="${PARROT_BRANCH:-main}"
REPO_URL="https://github.com/dozer54321/parrot-clicker.git"

install_timer() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Need root to install the auto-update timer."
    echo "  sudo $ROOT/deploy/vps/update.sh --install-timer"
    exit 1
  fi
  chmod +x "$ROOT/deploy/vps/update.sh"
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git checkout — auto-update timer was not installed."
    echo "  git clone ${REPO_URL}"
    echo "  cd parrot-clicker && sudo ./deploy/vps/install.sh your.hostname"
    exit 0
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "No systemd here. Check GitHub from cron instead:"
    echo "  */2 * * * * $ROOT/deploy/vps/update.sh"
    exit 0
  fi
  cat > /etc/systemd/system/parrot-update.service <<EOF
[Unit]
Description=Parrot Clicker — pull GitHub and rebuild when main moves
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${ROOT}
ExecStart=${ROOT}/deploy/vps/update.sh
EOF
  cat > /etc/systemd/system/parrot-update.timer <<EOF
[Unit]
Description=Check GitHub for a new Parrot Clicker push

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=15s
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now parrot-update.timer
  echo "Auto-update is on. A push to main rebuilds this machine within about 2 minutes."
  echo "  systemctl status parrot-update.timer"
  echo "  journalctl -u parrot-update.service -n 40 --no-pager"
}

rebuild() {
  if [ ! -f "$ROOT/parrot.env" ]; then
    echo "No parrot.env — run ./deploy/vps/start.sh <hostname> before updating."
    exit 1
  fi
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    echo "Docker is not available; skipped rebuild."
    exit 1
  fi
  local sha
  sha="$(git rev-parse --short HEAD)"
  echo "Rebuilding Parrot Clicker at ${sha}."
  local profiles=()
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'parrot-caddy'; then
    profiles=(--profile edge)
  fi
  docker compose "${profiles[@]}" --env-file "$ROOT/parrot.env" up -d --build
  echo "Rebuild finished (${sha}). Browser flocks are unchanged."
}

if [ "${1:-}" = "--install-timer" ]; then
  install_timer
  exit 0
fi

if [ "${1:-}" = "--rebuild" ]; then
  rebuild
  exit 0
fi

if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This folder is not a git checkout, so it cannot follow GitHub."
  echo "  git clone ${REPO_URL}"
  echo "  cd parrot-clicker && sudo ./deploy/vps/install.sh your.hostname"
  exit 1
fi

LOCK="$ROOT/.update.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "An update is already running."
  exit 0
fi

if ! git fetch --quiet origin "$BRANCH"; then
  echo "Could not fetch ${REPO_URL}."
  echo "If the repo is private, this machine needs a deploy key or GitHub login that can read it."
  exit 1
fi

LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/${BRANCH}")"
if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi

echo "GitHub moved ${LOCAL:0:7} -> ${REMOTE:0:7}. Updating."
git reset --hard "origin/${BRANCH}"
# The script on disk may have changed. Rebuild with the new copy.
exec "$ROOT/deploy/vps/update.sh" --rebuild
