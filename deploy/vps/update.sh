#!/bin/bash
# Swap in the public image when a push to main publishes one.
# Never uses git. Never asks for a GitHub username or token.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS || true

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

REV_URL="https://github.com/dozer54321/parrot-clicker/releases/download/rolling/REVISION"
IMG_URL="https://github.com/dozer54321/parrot-clicker/releases/download/rolling/parrot-image.tar.gz"
STATE="$ROOT/.autoupdate-rev"

install_timer() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Need root to install the auto-update timer."
    echo "  sudo $ROOT/deploy/vps/update.sh --install-timer"
    exit 1
  fi
  chmod +x "$ROOT/deploy/vps/update.sh"
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "No systemd here. Check for a new image from cron instead:"
    echo "  */2 * * * * $ROOT/deploy/vps/update.sh"
    exit 0
  fi
  cat > /etc/systemd/system/parrot-update.service <<EOF
[Unit]
Description=Parrot Clicker — load the public image when main publishes one
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GIT_TERMINAL_PROMPT=0
WorkingDirectory=${ROOT}
ExecStart=${ROOT}/deploy/vps/update.sh
EOF
  cat > /etc/systemd/system/parrot-update.timer <<EOF
[Unit]
Description=Check for a new Parrot Clicker image

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
  echo "Auto-update is on. A push to main is live within about 2 minutes."
  echo "No GitHub login on this machine."
  echo "  systemctl status parrot-update.timer"
  echo "  journalctl -u parrot-update.service -n 40 --no-pager"
}

if [ "${1:-}" = "--install-timer" ]; then
  install_timer
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is missing."
  exit 1
fi
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "Docker is not available."
  exit 1
fi
if [ ! -f "$ROOT/parrot.env" ]; then
  echo "No parrot.env yet. Install first."
  exit 1
fi

LOCK="$ROOT/.update.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "An update is already running."
  exit 0
fi

new="$(curl -fsSL --retry 2 --retry-delay 2 -A "ParrotClicker-updater/1.0" "$REV_URL" 2>/dev/null | tr -d '[:space:]' || true)"
if ! printf '%s' "$new" | grep -Eq '^[0-9a-f]{7,40}$'; then
  exit 0
fi
old=""
if [ -f "$STATE" ]; then
  old="$(tr -d '[:space:]' < "$STATE")"
fi
if [ "$new" = "$old" ]; then
  exit 0
fi

echo "New Parrot Clicker image ${new:0:7}."
tmp="$(mktemp)"
curl -fL --retry 3 --retry-delay 2 -A "ParrotClicker-updater/1.0" -o "$tmp" "$IMG_URL"
docker load -i "$tmp"
rm -f "$tmp"

if grep -q '^PARROT_IMAGE=' "$ROOT/parrot.env"; then
  sed -i.bak 's|^PARROT_IMAGE=.*|PARROT_IMAGE=parrot:local|' "$ROOT/parrot.env" && rm -f "$ROOT/parrot.env.bak"
else
  echo "PARROT_IMAGE=parrot:local" >> "$ROOT/parrot.env"
fi

profiles=()
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx 'parrot-caddy'; then
  profiles=(--profile edge)
fi
docker compose "${profiles[@]}" --env-file "$ROOT/parrot.env" up -d --no-build --force-recreate parrot
printf '%s\n' "$new" > "$STATE"
echo "Updated to ${new:0:7}. Browser flocks are unchanged."
