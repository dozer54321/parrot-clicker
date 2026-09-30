#!/bin/bash
# Install Parrot Clicker on the VPS. No git. No GitHub username.
# Save this file, then:
#   sudo bash /tmp/parrot-install.sh
# Hostname is parrot.yourmomon.top unless you pass another one.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
unset GIT_ASKPASS SSH_ASKPASS || true

if [ "$(id -u)" -ne 0 ]; then
  echo "Need sudo so Docker can be installed. Re-running with sudo..."
  exec sudo -E "$0" "$@"
fi

DOMAIN="${1:-parrot.yourmomon.top}"
ROOT=/opt/parrot-clicker
SRC_URL="https://codeload.github.com/dozer54321/parrot-clicker/tar.gz/refs/heads/main"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl

tmp="$(mktemp)"
stage="$(mktemp -d)"
keep="$(mktemp -d)"
cleanup() { rm -rf "$tmp" "$stage" "$keep"; }
trap cleanup EXIT

echo "Downloading Parrot Clicker. This does not ask for a GitHub login."
curl -fsSL --retry 3 --retry-delay 2 -A "ParrotClicker-install/1.0" -o "$tmp" "$SRC_URL"
tar -xzf "$tmp" -C "$stage"
src="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [ -z "$src" ] || [ ! -f "$src/docker-compose.yml" ]; then
  echo "The download did not contain Parrot Clicker."
  exit 1
fi

mkdir -p "$ROOT"
for f in parrot.env docker-compose.override.yml .autoupdate-rev; do
  if [ -f "$ROOT/$f" ]; then
    cp -a "$ROOT/$f" "$keep/"
  fi
done
cp -a "$src/." "$ROOT/"
for f in parrot.env docker-compose.override.yml .autoupdate-rev; do
  if [ -f "$keep/$f" ]; then
    cp -a "$keep/$f" "$ROOT/$f"
  fi
done

chmod +x "$ROOT/deploy/vps/"*.sh
"$ROOT/deploy/vps/install.sh" "$DOMAIN"
