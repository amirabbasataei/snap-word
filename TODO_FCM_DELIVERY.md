# TODO — FCM push delivery from the backend container

**Status:** client side is done; server-side delivery is blocked in the dev environment only.

## The issue

The backend container cannot reach Google (`oauth2.googleapis.com`, `fcm.googleapis.com`), so every push fails with:

```
notification: send failed ... Post "https://oauth2.googleapis.com/token": context deadline exceeded
```

### Root cause
- Google is not directly reachable from Iran. The dev host only reaches it through **Nekoray** (TUN proxy, `nekoray-tun`, listening on `127.0.0.1:2080`).
- Docker bridge traffic is not routed through that proxy, so the container has no outbound access to Google (even `example.com` times out over TCP).
- Nekoray's TUN subnet `172.19.0.0/24` also overlaps a Docker network (`172.19.0.0/16`), which can make routing worse.
- Not a code bug: the service-account key, project id (`zanjir-269aa`) and FCM code are in place. Verified: a `--network host` container reaches Google fine.

## Fix (permanent) — deploy to a foreign server
Planned once testing is finished. Nothing to change in code: place the key at `backend/secrets/fcm-service-account.json` (or set `FCM_SERVICE_ACCOUNT_JSON`) and set `FCM_PROJECT_ID=zanjir-269aa`.

## Workarounds for local testing (pick one)

1. **Run the backend on the host** (host already has Google via Nekoray):
   ```bash
   cd backend && docker compose stop app
   # backend/.env: DATABASE_URL / REDIS_URL -> localhost:5432 / localhost:6379
   FCM_SERVICE_ACCOUNT_JSON=secrets/fcm-service-account.json go run ./cmd/server
   ```
   Emulator reaches it at `10.0.2.2:8080`.

2. **Route the container through the proxy:**
   - Nekoray settings → enable "Allow connections from LAN" (listen on `0.0.0.0:2080`).
   - Add to the `app` service in `backend/docker-compose.yml`:
     ```yaml
     HTTPS_PROXY: http://172.20.0.1:2080
     NO_PROXY: postgres,redis,localhost
     ```
     (Go's `http.DefaultClient` honours it; only FCM/OAuth calls leave the container.)
   - `docker compose up -d --force-recreate app`.

## Verify
```bash
docker compose exec app wget -q -O- -T 8 https://oauth2.googleapis.com/token   # expect "404 Not Found" (= reachable)
docker compose logs app | grep -i notification                                  # no "send failed" after a challenge/friend request
```
Then: log in on the emulator, accept the dialog on the Friends tab, send a friend request / challenge from the second emulator, background the app, and confirm the system notification appears.

## Related follow-ups (not blocking)
- Send `data.route` with pushes (`/friends`, `/daily`, …) so tapping a notification deep-links (client already handles it).
- iOS: add `GoogleService-Info.plist` and upload an APNs key in Firebase.
- Drop the host-only workaround once the foreign server is live and remove the dev caveat in `CLAUDE.md` (§ FCM setup).
