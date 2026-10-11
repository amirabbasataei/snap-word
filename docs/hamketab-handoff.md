# Ham-Ketab (varaqa.ir) — handoff for the hamketab repo

Server side is done (2026-10-11); see [`server-runbook.md`](server-runbook.md). This
lists what has to change **inside the hamketab repo** so it deploys onto that layout.

## What the server looks like now

| Thing | Value |
|---|---|
| Domain | `varaqa.ir`, `www.varaqa.ir` (nginx `server_name`); DNS still at Parspack — move to ArvanCloud |
| SPA | nginx serves `/opt/hamketab/web/` (copy of the old `apps/web/dist`), SPA fallback, `/assets/` cached 1 year |
| API | `/api/x` → `127.0.0.1:13000/x` (prefix stripped, as before); `/docs` → API docs; OTP routes rate-limited 20/min per IP |
| API runtime | `/opt/hamketab/compose.yml`, service `api`, **interim**: stock `node:22-bookworm-slim` running `/opt/hamketab/legacy/apps/api/dist/main.js` (the old checkout, read-only). pm2 is removed. |
| Database | shared Postgres, host `postgres` on Docker network `infra`, database + role `hamketab` (not superuser; PostGIS 3.5 + uuid-ossp pre-created by the superuser) |
| Secrets | `/opt/hamketab/.env` (root-only): new `DB_PASSWORD`, new `JWT_SECRET`; `ARVAN_*` object-storage keys carried over unchanged; `CORS_ORIGIN=https://varaqa.ir,https://www.varaqa.ir,http://varaqa.ir,http://www.varaqa.ir` |
| Real client IP | nginx overwrites `X-Forwarded-For` with the real visitor IP (ArvanCloud-aware) |

## WHAT I MUST DO IN THE HAM-KETAB FOLDER

1. **Retire the old `deploy.sh`.** Its `install`/`update` would reinstall pm2, rewrite nginx
   and start a Postgres on `0.0.0.0:5432` — never run it against the server again. Delete it
   (and `save.sh` if it only served that flow).
2. **`apps/api/Dockerfile`** (new) — multi-stage, pnpm workspace:
   build stage `node:22-bookworm-slim` + `corepack enable`, `pnpm install --frozen-lockfile`,
   `pnpm --filter api build`, `pnpm --filter api deploy --prod /out` (pnpm 10 needs
   `--legacy` or `inject-workspace-packages=true`); runtime stage `node:22-bookworm-slim`,
   `COPY --from=build /out /app`, `WORKDIR /app`, `USER node`, `ENV NODE_ENV=production`,
   `EXPOSE 3000`, `CMD ["node","dist/main.js"]`. Plus a **`.dockerignore`** (node_modules,
   dist, .git, .env*, apps/web).
3. **`deploy/compose.yml`** (new, the canonical copy of `/opt/hamketab/compose.yml`):
   service `api`, `image: ${APP_IMAGE}`, `env_file: .env`, `ports: ["127.0.0.1:13000:3000"]`,
   `networks: [infra]` (external), healthcheck on `/health`, `restart: unless-stopped`,
   json-file log rotation — i.e. the server file **without** the interim `working_dir`,
   `command` and `volumes` lines.
4. **`scripts/deploy.sh`** (new) — run from your machine:
   - API: `docker build --platform linux/amd64 -f apps/api/Dockerfile -t hamketab-api:<git sha> .`
     → `docker save … | gzip | ssh root@185.110.191.158 'gunzip | docker load'`
     → `scp deploy/compose.yml root@…:/opt/hamketab/compose.yml`
     → on the server: set `APP_IMAGE=hamketab-api:<sha>` in `/opt/hamketab/.env`,
     `docker compose up -d`, poll `curl -fs 127.0.0.1:13000/health`; prune old tags (keep 3).
   - Web: `pnpm --filter web build` with `VITE_API_URL` **unset** (defaults to same-origin
     `/api`) → `rsync -a --delete apps/web/dist/ root@…:/opt/hamketab/web/`.
   - Never build on the server (1 vCPU / 2 GB).
5. **Env / config:**
   - `.env.example`: document the server values — `DB_HOST=postgres`, `DB_USERNAME=hamketab`,
     `DB_NAME=hamketab`, `CORS_ORIGIN=https://varaqa.ir,https://www.varaqa.ir`, `NODE_ENV=production`.
     No real secrets in the repo.
   - Root `docker-compose.yml` (local dev DB): bind `127.0.0.1:5432:5432` and mark it dev-only.
   - `main.ts`: `app.getHttpAdapter().getInstance().set('trust proxy', 1)` so `req.ip` is the
     real visitor (nginx is the single trusted hop). `app.listen(port, '0.0.0.0')` is fine
     inside the container.
   - **Cookies:** the API uses bearer tokens (no cookie code found) — nothing to set. If you add
     cookies: no `Domain` attribute (host-only on `varaqa.ir`), `Secure`, `HttpOnly`, `SameSite=Lax`.
6. **Frontend secret:** `VITE_OPENROUTER_API_KEY` is read in the web app. Every `VITE_*` value
   is baked into public JavaScript. (The current build has no key in it.) Move the OpenRouter call
   behind an API endpoint, keep the key in `/opt/hamketab/.env`, and rotate any key that was
   ever set in a web build.
7. **Migrations:** production runs `DB_SYNCHRONIZE=true` (TypeORM rewrites the schema at boot —
   risky). Add a TypeORM `DataSource` file, generate a baseline migration from the current
   entities, mark it applied on the server once (`INSERT INTO migrations …`, or generate it
   against the live schema so it is empty), then set `DB_SYNCHRONIZE=false` and
   `migrationsRun: true` (or run `migration:run` in deploy.sh before `up -d`).
8. **Object storage keys:** the `ARVAN_*` keys were copied as-is. Rotate them in the
   ArvanCloud panel and update `/opt/hamketab/.env`.
9. **After the first image deploy** (server): `rm -rf /opt/hamketab/legacy` (holds the old
   checkout incl. `.git`; its `.env` files were already removed).

## Prompt for a Claude Code session in the hamketab folder

```
Context: this repo (hamketab, NestJS API in apps/api + Vite React PWA in apps/web, pnpm
workspace) is deployed on a shared Ubuntu host root@185.110.191.158 (1 vCPU, 2 GB RAM)
that was restructured on 2026-10-11. Server layout (already in place, do not change it):
- Host nginx is the only public entry. varaqa.ir serves the SPA from /opt/hamketab/web
  and proxies /api/x to 127.0.0.1:13000/x (prefix stripped) and /docs to the API.
  nginx overwrites X-Forwarded-For with the real client IP.
- The API runs from /opt/hamketab/compose.yml (service "api", env_file /opt/hamketab/.env,
  ports 127.0.0.1:13000:3000, external Docker network "infra"). It currently runs the old
  build via an interim stock node image + a read-only mount of /opt/hamketab/legacy.
- Postgres is a shared PostGIS 16 instance: host "postgres" on the "infra" network,
  database and role "hamketab" (not superuser; postgis and uuid-ossp already created).
- Secrets live only in the root-only /opt/hamketab/.env on the server. Images must be
  built locally and shipped with `docker save | ssh docker load` — never build on the server.

Tasks (make the changes, run lint/tests/build locally, do not touch the server unless I say so):
1. Add apps/api/Dockerfile (multi-stage, node:22-bookworm-slim, pnpm via corepack,
   `pnpm --filter api deploy --prod`, non-root user, CMD node dist/main.js, port 3000) and
   a .dockerignore. Verify `docker build --platform linux/amd64` works and the container
   starts and serves /health against a local Postgres.
2. Add deploy/compose.yml matching the server file minus the interim lines
   (image: ${APP_IMAGE}, env_file .env, 127.0.0.1:13000:3000, network infra external,
   healthcheck on /health, json-file log rotation).
3. Replace deploy.sh with scripts/deploy.sh that: builds and ships the API image tagged
   with the git sha, copies deploy/compose.yml to /opt/hamketab/compose.yml, sets
   APP_IMAGE in /opt/hamketab/.env, runs `docker compose up -d`, health-checks
   127.0.0.1:13000/health over SSH, keeps the 3 newest image tags; and builds apps/web with
   VITE_API_URL unset and rsyncs dist/ to /opt/hamketab/web/ (with --dry-run and --web-only/
   --api-only flags). Delete the old deploy.sh (it installs pm2/nginx/Postgres and must never
   run again).
4. In apps/api/src/main.ts set Express 'trust proxy' to 1.
5. Introduce TypeORM migrations: a DataSource config, a baseline migration that matches the
   current schema (the production DB already has it), npm scripts for generate/run, and
   DB_SYNCHRONIZE=false for production with migrations run on deploy. Explain the one-time
   step to mark the baseline as applied on the existing database.
6. Move the OpenRouter call from the web app to a new API endpoint so no VITE_ secret is
   shipped to browsers; the key becomes OPENROUTER_API_KEY in the API env.
7. Update .env.example files (server values: DB_HOST=postgres, CORS_ORIGIN for
   https://varaqa.ir and https://www.varaqa.ir), bind the dev docker-compose Postgres to
   127.0.0.1, and update CLAUDE.md/README with the new deploy flow.
Commit in logical commits when done; do not push.
```
