# Deployment to-do

Open items from the deployment review of 2026-10-27 (see [`deployment-guide.md`](deployment-guide.md)).
Ordered by impact. Nothing here blocks routine deploys. Tick and date an item when it is done.

## High

- [ ] **Off-server backups.** All backups (`/var/backups/infra`) are on the same disk as the data; a disk or host loss
  loses everything. Copy `deploy/host/post-backup.d/offsite.sh.example` to `/opt/infra/post-backup.d/offsite.sh`
  on the server, choose rsync-over-SSH or rclone to ArvanCloud Object Storage, `chmod +x`. Keep credentials on the
  server only. Afterwards, test a restore from the off-site copy.
- [ ] **Migrations are forward-only on deploy.** Reverting `APP_IMAGE` leaves the schema at the newer version. Adopt
  expand-then-contract for schema changes (add first, drop in a later release) and take `pg-backup` before any
  risky migration. Optionally make `deploy_backend.sh` run `pg-backup` on the server first.
- [ ] **Reject an empty `JWT_SECRET` at startup when `ENV=prod`** (`backend/internal/config/config.go` falls back to
  `""`; only the prod compose guards it with `:?`). Add a fatal check in `cmd/server/main.go`.

## Medium

- [ ] **Redis eviction vs. durable data.** Prod Redis is `maxmemory 128mb` + `allkeys-lru` but holds the weekly
  leaderboard and admin sessions; under memory pressure they can be evicted. Switch to `volatile-lru` / `noeviction`
  or raise the limit, and watch `used_memory` (`deploy/sites/wordchain/compose.yml`).
- [ ] **Config drift.**
  - `.env.example`: add `ADMIN_API_KEY`, `ADMIN_SESSION_TTL`, `ADMIN_IP_ALLOWLIST`.
  - Prod compose: pass `OTP_CODE_TTL` and `OTP_RESEND_COOLDOWN` through (code defaults apply today).
  - `backend/docker-compose.yml` (local): pass the two admin vars.
- [ ] **`backend/Dockerfile` cannot build the admin panel.** An image built without `pnpm -C admin build` serves a
  503 "panel not built". Either add a Node build stage or make the Dockerfile fail when `dist/` has no `index.html`.
- [ ] **No pre-flight for an image before it goes live.** `--dry-run` builds and diffs compose but never runs the
  image. Idea: start the new image on a second loopback port against a scratch database and hit `/health`
  before switching.
- [ ] **Deploys cause a few seconds of downtime** (container recreate, WebSockets drop; clients reconnect within the
  30 s grace). No blue/green; schedule releases off-peak.

## Low

- [ ] **`host_sync.sh` can touch every site.** Editing the Postgres `command:` args in `deploy/host/compose.yml`
  recreates `infra-postgres` (brief outage for all sites). Review `--dry-run` output and do it off-peak.
- [ ] **`sites-available/zanjir-https` is generated, not in git.** Rebuilding the host needs `site-https zanjir`
  again; consider committing a rendered copy under `deploy/host/nginx/`.
- [ ] **Host provisioning is not scripted** (swap, ufw, sshd hardening, package install). The guide reconstructs it
  (§4.1); consider a `deploy/host/bootstrap.sh`.
- [ ] **Leftovers from the runbook:** delete the stale `ufw allow 8080/tcp` rule; delete `/root/pre-migration/`.
- [ ] **Still unverified/unbuilt:** Kavenegar SMS delivery, iOS push (APNs key + `GoogleService-Info.plist`), admin
  TOTP (stage A7). Until A7 the panel is protected only by password + throttling + optional `ADMIN_IP_ALLOWLIST`.
