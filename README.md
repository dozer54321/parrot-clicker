# Parrot Clicker

Tap the macaw. Buy roosts. The flock keeps making parrots while you are gone.

## Install

Point a DNS A record at the VPS first. The app does not take ports 80 or 443 when Caddy is already running. It listens on `127.0.0.1:3060` and piggybacks that Caddy (same layout as Momon and Take-Home).

```bash
git clone https://github.com/dozer54321/parrot-clicker.git
cd parrot-clicker
sudo ./deploy/vps/install.sh parrots.yourmomon.top
```

This repo is private. The VPS needs read access before `git clone` and before later pulls — a read-only deploy key, or `gh auth login` as the user that will run the timer (root, if you install with sudo).

Docker is already installed and the repo is already on the machine:

```bash
./deploy/vps/start.sh parrots.yourmomon.top
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
sudo ./deploy/vps/repair.sh parrots.yourmomon.top
```

Player saves stay in the browser. `backups/` only keeps `parrot.env`.

## Auto-update

`install.sh` / `start.sh` (as root) enable `parrot-update.timer`. Every 2 minutes it fetches `main`. When GitHub has a new commit it resets to that commit and runs `docker compose up -d --build`. Nothing else on the box is rebuilt. Browser flocks are not touched.

```bash
systemctl status parrot-update.timer
journalctl -u parrot-update.service -n 40 --no-pager
sudo ./deploy/vps/update.sh
```

Push to `main` on [dozer54321/parrot-clicker](https://github.com/dozer54321/parrot-clicker) and the installed copy follows.

No systemd (cron instead):

```bash
*/2 * * * * /path/to/parrot-clicker/deploy/vps/update.sh
```
