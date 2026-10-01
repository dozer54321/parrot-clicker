# Parrot Clicker

Tap the macaw. Buy roosts. The flock keeps making parrots while you are gone.

Live site: [parrot.yourmomon.top](https://parrot.yourmomon.top)

## Install

Point a DNS A record for `parrot.yourmomon.top` at the VPS first. The app does not take ports 80 or 443 when Caddy is already running. It listens on `127.0.0.1:3060` and piggybacks that Caddy.

This does not use git and does not ask for a GitHub username.

```bash
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL -o /tmp/parrot-install.sh https://raw.githubusercontent.com/dozer54321/parrot-clicker/main/deploy/vps/bootstrap.sh
sudo bash /tmp/parrot-install.sh
```

That installs for `parrot.yourmomon.top`. Already unpacked on the machine:

```bash
sudo ./deploy/vps/install.sh
```

| Port | App |
| --- | --- |
| 3010 | Take-Home |
| 3060 | Parrot Clicker |
| 3080 | Momon |
| 3090 | Eye tracker |

`start.sh` picks one of these:

- Host Caddy (systemd or a running `caddy`) — append a marked site block that proxies `127.0.0.1:3060`
- A Caddy container — join that Docker network and proxy `parrot-app:3000`
- No Caddy — start one with Compose profile `edge`

Re-apply the site block without a rebuild:

```bash
sudo ./deploy/vps/repair.sh parrot.yourmomon.top
```

Player saves stay in the browser. `backups/` only keeps `parrot.env`.

## If the browser says “Secure connection failed”

`www.parrot.yourmomon.top` has no DNS record, and the name was never added to Requestick's Caddy (the one already on port 443). On the VPS:

```bash
curl -fsSL -o /tmp/fix-tls.sh https://raw.githubusercontent.com/dozer54321/parrot-clicker/main/deploy/vps/fix-tls.sh
sudo bash /tmp/fix-tls.sh
```

Wait about half a minute, then open https://parrot.yourmomon.top again. Add a DNS record for `www` only if you actually want that name.

## Auto-update

Every push to `main` publishes a public image. The VPS checks about every 2 minutes and loads it. No clone, no token, no username prompt.

```bash
systemctl status parrot-update.timer
journalctl -u parrot-update.service -n 40 --no-pager
```

If the timer was never installed:

```bash
sudo /opt/parrot-clicker/deploy/vps/update.sh --install-timer
```
