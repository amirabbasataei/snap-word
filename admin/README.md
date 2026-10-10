# زنجیر admin panel

React 18 + TypeScript + Vite + Tailwind v4 (RTL Persian). Plan and per-stage log: `../ADMIN_PLAN.md`.

```bash
pnpm install
pnpm dev          # http://localhost:5173/admin/ — proxies /api to the backend on :8080
pnpm typecheck && pnpm lint && pnpm test
pnpm build        # → ../backend/internal/adminui/dist (embedded in the Go binary), then rebuild the backend
```

- Tokens (the only place hex values may appear): `src/styles/tokens.css`. Logical CSS only — `src/test/lint-rules.test.ts` fails on hex outside tokens.css and on `ml-/mr-/left-/right-` style physical utilities.
- `/admin/kit` (dev server only) is a gallery of the component kit with sample data.
- Needs a backend with an admin account: `docker compose exec app /adminctl create-user <name> owner`.
