# Parrot Clicker

Tap the macaw. Buy roosts. The flock keeps making parrots while you are gone.

Live site: [parrot.yourmomon.top](https://parrot.yourmomon.top)

## Install

Point a DNS A record for `parrot.yourmomon.top` at the VPS first. Paste one line at a time. No git, no username, no compile.

```bash
sudo apt-get update && sudo apt-get install -y curl
```

```bash
curl -fsSL -o /tmp/parrot-install.sh https://raw.githubusercontent.com/dozer54321/parrot-clicker/main/deploy/vps/bootstrap.sh
```

```bash
sudo bash /tmp/parrot-install.sh
```

It uses the Caddy you already run (same as Take-Home and Momon) and listens on `127.0.0.1:3060`.

| Port | App |
| --- | --- |
| 3010 | Take-Home |
| 3060 | Parrot Clicker |
| 3080 | Momon |
| 3090 | Eye tracker |

Player saves stay in the browser.

## Auto-update

Every push to `main` publishes a public image. The VPS loads it on its own. No login.

```bash
systemctl status parrot-update.timer
```
