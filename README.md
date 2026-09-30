# Parrot Clicker

Tap the macaw. Buy roosts. The flock keeps making parrots while you are gone.

## On the VPS

This uses the same Docker + Caddy arrangement as Momon and Take-Home. It does not bind ports 80 or 443 unless nothing else is serving them. The app is published on `127.0.0.1:3060` (not 3010, 3080, or 3090).

```bash
sudo ./deploy/vps/install.sh parrots.yourmomon.top
```

If Docker is already up:

```bash
./deploy/vps/start.sh parrots.yourmomon.top
```

`start.sh` looks for Caddy the way Momon does:

- host Caddy (systemd or a running `caddy` process) — append a marked site block that proxies `127.0.0.1:3060`
- a Caddy container (Requestick and friends) — join that Docker network and proxy `parrot-app:3000`
- no Caddy at all — start one with Compose profile `edge`

Re-apply the site block with `sudo ./deploy/vps/repair.sh your.hostname`. Player saves stay in the browser.
