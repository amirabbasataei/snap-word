# Server plan — 185.110.191.158 (multi-site host)

Single Ubuntu 26.04 box, 1 vCPU, 2 GB RAM, 38 GB disk. Hosts **Zanjir** (this repo),
**Ham-Ketab** (`varaqa.ir`) and further sites. Everything here is test/dev data.
Operational runbook: [`server-runbook.md`](server-runbook.md). Config sources: [`../deploy/`](../deploy/).

## Architecture

```
Internet ─► ArvanCloud CDN ─► host nginx :80/:443 (only public web entry; unknown Host → dropped)
                               ├─ amirabbasataei.ir        → 127.0.0.1:18080  zanjir app   (/opt/wordchain)
                               ├─ varaqa.ir                → static /opt/hamketab/web + /api → 127.0.0.1:13000 (/opt/hamketab)
                               └─ <new site>               → 127.0.0.1:140xx  (/opt/<site>, made by new-site)
         direct :8080 (legacy) ─► nginx :8080 → 127.0.0.1:18080   (installed Zanjir apps; remove later)

/opt/infra      compose "infra": postgres (postgis/postgis:16-3.5), network "infra",
                bin/ (new-site, pg-backup, pg-restore-test, arvan-ips-refresh), backup hooks
/opt/<site>     compose per site: app containers only (no nginx, no postgres), joins "infra",
                publishes only on 127.0.0.1, secrets in root-only .env
```

- **One Postgres server**, one database + one login role per app (role owns its DB, `CONNECT`
  revoked from `PUBLIC`, roles are not superusers). Reachable as host `postgres` on the
  `infra` Docker network and on `127.0.0.1:5432` (for SSH tunnels only).
- **Images are built on the developer machine** and shipped with `docker save | ssh docker load`.
  The server never runs `docker build` (1 vCPU / 2 GB — the cause of the hung deploy).
- Redis stays per-app (Zanjir only; ~20 MB).

## Port map

| Port | Bound to | Owner | Notes |
|---|---|---|---|
| 22 | public | sshd | key-only |
| 80, 443 | public | nginx | per-site `server_name`; default server drops |
| 8080 | public | nginx | legacy Zanjir URL for installed apps — remove once migrated |
| 5432 | 127.0.0.1 | infra-postgres | tunnel only |
| 18080 | 127.0.0.1 | wordchain app | |
| 13000 | 127.0.0.1 | hamketab api | |
| 14000–14999 | 127.0.0.1 | new sites | allocated by `new-site`, registry `/opt/infra/ports` |

## Order of work

1. **Safety net**: dump both databases to `/root/pre-migration/`; back up `/etc/nginx`, `/etc/ssh`, compose files and `.env`s.
2. **Host hardening**: 2 GB swapfile (swappiness 10); ufw allow 22/80/443/8080 then enable;
   sshd key-only (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`) validated with `sshd -t`
   and tested from a second session before the first is closed; `server_tokens off`.
3. **Infra Postgres**: new `/opt/infra` stack with tuned memory settings and a fresh superuser password.
4. **Zanjir**: new DB role/password, restore dump, rotate JWT secret + add `ADMIN_API_KEY`;
   compose switches to a shipped image + infra network; remove old Postgres container/volume
   and the rsynced source tree. Remove the `/zanjir` prefix work from the repo; panel stays at `/admin/`.
5. **Ham-Ketab**: new DB role/password (non-superuser), restore dump; API moves from pm2 on
   `*:3000` to a Compose service on `127.0.0.1:13000` (interim: runs the existing build read-only);
   old `hamketab-db` (public 5432) removed; pm2 disabled.
6. **nginx**: real-IP from ArvanCloud ranges (auto-refreshed weekly), shared headers/rate limits,
   one file per site, default server returning 444; `nginx -t` then reload.
7. **Backups**: nightly systemd timer (`pg_dump -Fc` per DB + globals + hook scripts), 7 daily /
   4 weekly retention, restore test.
8. **new-site** script + runbook; admin account; seed avatars; verification; docs; commits.

## Rollback notes

| Change | Rollback |
|---|---|
| ufw | `ufw disable` (provider console if SSH is lost) |
| sshd | `cp /root/pre-migration/etc/ssh/sshd_config /etc/ssh/ && systemctl reload ssh` |
| nginx | `rsync -a --delete /root/pre-migration/etc/nginx/ /etc/nginx/ && nginx -t && systemctl reload nginx` |
| Zanjir DB | old volume `wordchain_postgres_data` is kept until verification passes; dump in `/root/pre-migration/` |
| Ham-Ketab | old volume `hamketab_pgdata` kept until verification; `pm2 resurrect` restores the old API |
| Swap | `swapoff /swapfile` and remove the fstab line |

## Verification checklist (executed 2026-10-11 — all passed)

- [x] Public listeners only 22, 80, 443, 8080; external scan: 3000, 5432, 6379, 13000, 18080 closed
- [x] ufw active; sshd key-only, verified from a fresh session (both changes had auto-rollback timers)
- [x] `nginx -t` ok; unknown Host on :80 → closed (444); unknown SNI on :443 → handshake rejected;
      `amirabbasataei.ir` → Zanjir; `Host: varaqa.ir` → Ham-Ketab SPA + `/api/health`
- [x] Zanjir via domain and :8080: `/health`, REST, 16 avatars + image, authenticated REST,
      WebSocket `101 Switching Protocols`, admin login/me/dashboard, panel assets
- [x] Ham-Ketab: API container healthy, PostGIS 3.5.2, all 14 tables match the cutover dump; pm2 removed
- [x] Real client IP in logs through ArvanCloud; forged `X-Forwarded-For` ignored (direct and via edge)
- [x] nginx rate limits answer 429 (`admin_login`, `auth`)
- [x] Backup via systemd ok; restore test OK for both DBs (row counts match); retention pruning tested
- [x] Swap active; no container publishes a non-loopback port
- [x] Origin HTTPS for amirabbasataei.ir (Let's Encrypt, renewal dry run ok); edge HTTPS is the owner's step

## Outcome notes

- **No compromise found** while 5432 was public (2026-09-23 → 2026-10-11): 1,624 failed
  password attempts, all generic usernames (`postgres` 1,228, `wog`, `pgg_superadmins`, `admin`,
  `n8n`, …), none for `hamketab`; password was a custom 32-char one; no unknown roles, no
  non-extension C functions, no odd processes, cron jobs or SSH keys. All accepted SSH logins
  (7 days) used the owner's two keys. There were ~9k failed SSH attempts/day; password
  auth is now off, so they can no longer succeed.
- Shared Postgres runs PostgreSQL 16.9 (`postgis/postgis:16-3.5`), up from 16.4.
- The first cutover attempt stopped early: `docker exec -i` in a helper consumed the piped
  script. Fixed in `lib-pg.sh` (`psql_su` vs `psql_in`); remote scripts are now copied, not piped.
