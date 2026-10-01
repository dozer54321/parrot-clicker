# Parrot Clicker

Tap the macaw. Buy roosts. The flock keeps making parrots while you are gone.

Live site: [parrot.yourmomon.top](https://parrot.yourmomon.top)

## Install

Point a DNS A record for `parrot.yourmomon.top` at the VPS first. This does not use git and does not ask for a GitHub username. It does not take ports 80 or 443 when Caddy is already running (same hook as Momon). The app listens on `127.0.0.1:3060`.

```bash
sudo apt-get update && sudo apt-get install -y curl
curl -fsSL -o /tmp/parrot-install.sh https://raw.githubusercontent.com/dozer54321/parrot-clicker/main/deploy/vps/bootstrap.sh
sudo bash /tmp/parrot-install.sh
```

A blank page is Caddy’s empty 502: the certificate is fine, the app is not reachable. On the VPS:

```bash
curl -fsSL -o /tmp/fix-upstream.sh https://raw.githubusercontent.com/dozer54321/parrot-clicker/main/deploy/vps/fix-upstream.sh
sudo bash /tmp/fix-upstream.sh
```


| Port | App |
| --- | --- |
| 3010 | Take-Home |
| 3060 | Parrot Clicker |
| 3080 | Momon |
| 3090 | Eye tracker |

`www` is added only when that DNS record exists. `www.parrot.yourmomon.top` does not.

Player saves stay in the browser. `backups/` only keeps `parrot.env`.

## Auto-update

Every push to `main` publishes a public image. The VPS checks about every 2 minutes and loads it. No clone, no token, no username prompt.

```bash
systemctl status parrot-update.timer
journalctl -u parrot-update.service -n 40 --no-pager
```
