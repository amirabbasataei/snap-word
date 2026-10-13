# Server runbook — 185.110.191.158

How the shared host is laid out and how to operate it. Design and history:
[`server-plan.md`](server-plan.md). Every file under `/opt/infra` and the
managed nginx files come from [`deploy/host/`](../deploy/host/) in this repo;
edit them here and run `bash scripts/host_sync.sh`.

## Layout

| Path | What |
|---|---|
| `/opt/infra/` | compose `infra` (shared Postgres `infra-postgres`, PostGIS 16-3.5), `bin/`, `templates/`, backup hooks, `ports` registry, `.env` (superuser password) |
| `/opt/wordchain/` | Zanjir: `compose.yml` (app + redis), `.env`, `secrets/fcm-service-account.json` |
| `/opt/hamketab/` | Ham-Ketab: `compose.yml` (api), `.env`, `web/` (SPA served by nginx), `legacy/` (old checkout the interim API runs from) |
| `/opt/<site>/` | sites made by `new-site`: `compose.yml`, `.env`, optional `web/` |
| `/etc/nginx/conf.d/00-realip-arvan.conf` | generated weekly from ArvanCloud's ranges |
| `/etc/nginx/conf.d/10-common.conf` | maps, rate-limit zones, log format |
| `/etc/nginx/snippets/site-<name>.conf` | a site's locations (shared by its :80 and :443 servers) |
| `/etc/nginx/sites-available/<name>[-https]` | server blocks; `00-default` drops unknown hosts (444 / TLS reject) |
| `/var/backups/infra/{daily,weekly}/` | backups (root-only) |
| `/root/pre-migration/` | one-off dumps/configs from the 2026-10-11 migration — delete after ~1 week |

CLI on the server (all in `/usr/local/sbin`): `new-site`, `site-https`, `site-db`,
`pg-backup`, `pg-restore-test`, `arvan-ips-refresh`.

### Port map

| Port | Bound to | Owner |
|---|---|---|
| 22 | public | sshd (keys only) |
| 80, 443 | public | nginx |
| 8080 | closed | legacy Zanjir URL — nginx server removed 2026-10-13 (no installed clients); the leftover `ufw allow 8080/tcp` rule can be deleted |
| 5432 | 127.0.0.1 | infra-postgres (`ssh -L 5432:127.0.0.1:5432 root@185.110.191.158` for a GUI client) |
| 18080 | 127.0.0.1 | Zanjir app |
| 13000 | 127.0.0.1 | Ham-Ketab API |
| 14000+ | 127.0.0.1 | new sites (`/opt/infra/ports`) |

**Rule: never publish a container port without `127.0.0.1:`** — Docker writes its own
iptables rules and bypasses ufw.

## Deploying

- **Zanjir backend + panel:** `bash scripts/deploy_backend.sh` (builds the panel and the
  image locally, ships it with `docker save | ssh docker load`, updates `APP_IMAGE`,
  restarts, health-checks). The server never builds images. Rollback: see the script header.
- **Host config (nginx, timers, scripts, Postgres settings):** `bash scripts/host_sync.sh`
  (`--dry-run` to preview). nginx is checked with `nginx -t` and reloaded; on failure the
  previous `/etc/nginx` is restored.
- **Admin accounts:** `bash scripts/admin_user.sh <username> [role]` (interactive), or on the
  server non-interactively: `printf '%s\n' "$PW" | docker compose -f /opt/wordchain/compose.yml exec -T app /adminctl create-user <name> owner`.

## Adding a site (e.g. tomorrow's)

1. **ArvanCloud** — add the domain, switch its nameservers at the registrar to the two
   Arvan NS it shows, add `A @ → 185.110.191.158` (and `www`), proxy **on**. Wait until
   `dig +short NS <domain>` shows `*.ns.arvancdn.ir`.
2. **Server** — pick a short name (it becomes the DB, role, directory and nginx name):
   ```bash
   ssh root@185.110.191.158
   new-site shop shop.ir www.shop.ir --mode spa      # or --mode proxy | static; --postgis; --dry-run first
   ```
   This creates database + role `shop` (random password), `/opt/shop/{compose.yml,.env,web/}`,
   a loopback port (14000+), `snippets/site-shop.conf` + `sites-available/shop`, and reloads nginx.
   The database is in the nightly backup automatically.
3. **App** — build on your machine and ship:
   ```bash
   docker build --platform linux/amd64 -t shop:$(git rev-parse --short HEAD) .
   docker save shop:<tag> | gzip | ssh root@185.110.191.158 'gunzip | docker load'
   ```
   On the server: put `APP_IMAGE=shop:<tag>` and the app's settings into `/opt/shop/.env`
   (`DATABASE_URL`/`DB_*` are already there; the DB host is `postgres`), then
   `cd /opt/shop && docker compose up -d && docker compose logs -f`.
   Static files: `rsync -a --delete dist/ root@185.110.191.158:/opt/shop/web/`.
4. **Check** — `curl -H 'Host: shop.ir' http://185.110.191.158/` from anywhere, then via the domain.
5. **HTTPS** — once the domain resolves through Arvan: `site-https shop` (see below).
6. Adjust `/etc/nginx/snippets/site-shop.conf` if needed (login rate limit, body size,
   `/api` prefix handling), `nginx -t && systemctl reload nginx`.
   To keep it in git, copy the site's files into `deploy/host/nginx/` (then `install.sh` manages them).

## HTTPS

- **Origin certificate:** `site-https <name>` issues a Let's Encrypt cert via HTTP-01
  (`/var/www/acme`, works through ArvanCloud as long as the edge does not force HTTPS
  before it succeeds) and enables `sites-available/<name>-https`. `certbot.timer` renews;
  a deploy hook reloads nginx. `--dry-run` uses LE staging. Done for `zanjir` (2026-10-11).
- **ArvanCloud edge (panel, per domain):** *HTTPS settings* → enable HTTPS and issue the free
  edge certificate; *Origin/Load balancer settings* → origin protocol **HTTPS** (port 443)
  once the origin cert exists, otherwise HTTP. Only then turn on the edge *HTTP→HTTPS
  redirect*, and later HSTS. The Zanjir :80 server redirects to HTTPS itself when `$edge_proto` (from
  `X-Forwarded-Proto`, else the scheme) is `http` — ACME challenges are exempt, requests the
  edge forwards for HTTPS visitors are not redirected (verified 2026-10-13, no loop).
  Other sites still don't redirect.
- Zanjir client default is `https://`; Android cleartext is allowed only in the debug manifest.

## Backups

- `infra-backup.timer` 00:00 UTC (03:30 Iran): `pg_dump -Fc` of every database +
  `pg_dumpall --globals-only` + hooks in `/opt/infra/backup.d/` (Zanjir's Redis) + `SHA256SUMS`
  + per-table row counts. Keeps 7 daily, 4 weekly (Fridays).
- `infra-restore-test.timer` Fri 01:00 UTC: restores the newest backup into scratch DBs and
  compares tables/row counts (`journalctl -u infra-restore-test`). Run by hand: `pg-restore-test`.
- **Off-server copy (not set up):** `cp /opt/infra/post-backup.d/offsite.sh.example
  /opt/infra/post-backup.d/offsite.sh`, pick rsync-over-SSH or rclone to S3 (ArvanCloud
  Object Storage), `chmod +x`. Credentials stay on the server.
- **Restore a database:**
  ```bash
  B=/var/backups/infra/daily/<stamp>
  cd /opt/<site> && docker compose stop                       # stop the app
  docker exec infra-postgres psql -U postgres -c 'DROP DATABASE <db> WITH (FORCE)' -c 'CREATE DATABASE <db> OWNER <db>'
  # PostGIS sites: docker exec infra-postgres psql -U postgres -d <db> -c 'CREATE EXTENSION postgis'
  docker exec -i infra-postgres pg_restore -U postgres --no-owner --no-acl --role=<db> -d <db> < $B/<db>.dump
  docker compose start
  ```
  ("must be owner of extension" errors on `COMMENT ON EXTENSION` are harmless.)

## Secrets

All root-only (`600`), never in git: `/opt/infra/.env` (Postgres superuser),
`/opt/<site>/.env` (DB password, JWT/app secrets), `/opt/wordchain/secrets/`.
Rotate a DB password: `site-db password <name>` → put it in `/opt/<name>/.env` →
`docker compose up -d`. Everything was rotated on 2026-10-11.

## Security baseline

- ufw: deny incoming except 22, 80, 443 (a stale 8080 allow rule may remain; nothing listens). sshd: keys only, `PermitRootLogin prohibit-password`
  (`/etc/ssh/sshd_config.d/00-hardening.conf`).
- nginx: unknown Host → 444, unknown SNI → handshake rejected; real client IP only from
  ArvanCloud ranges ([official list](https://www.arvancloud.ir/en/ips.txt), refreshed weekly by
  `arvan-ips.timer`); `X-Forwarded-For` is overwritten with that IP before reaching apps;
  login/OTP endpoints rate-limited (`admin_login` 5/min, `auth` 20/min per IP).
- 2 GB swap (`vm.swappiness=10`).

## Rollback / recovery

- Locked out of SSH: provider web console → `rm /etc/ssh/sshd_config.d/00-hardening.conf && systemctl reload ssh` / `ufw disable`.
- nginx broken: `nginx -t` shows the file; `/root/pre-migration/etc/nginx` is the pre-2026-10-11 config.
- Bad Zanjir deploy: set the previous `APP_IMAGE` in `/opt/wordchain/.env`, `docker compose up -d app`
  (`docker images wordchain-app` lists the three kept tags).
