#!/usr/bin/env bash
# Applies /opt/infra (synced from deploy/host by scripts/host_sync.sh) to the host:
# systemd timers, nginx shared config + managed site files, CLI symlinks, Postgres.
# Idempotent. nginx is validated with nginx -t and reloaded (never restarted);
# on failure the previous /etc/nginx is restored.
set -euo pipefail
cd /opt/infra
chmod 700 /opt/infra; [[ -f .env ]] && chmod 600 .env
[[ -f ports ]] || printf '18080 wordchain\n13000 hamketab\n' > ports

# CLI
for b in new-site site-https site-db pg-backup pg-restore-test arvan-ips-refresh; do
  ln -sf "/opt/infra/bin/$b" "/usr/local/sbin/$b"
done

# Postgres
docker compose -f compose.yml up -d --wait

# systemd
install -m 644 systemd/*.service systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now infra-backup.timer infra-restore-test.timer arvan-ips.timer >/dev/null

# nginx
backup="$(mktemp -d)"; cp -a /etc/nginx "$backup/"
restore() { echo "nginx config invalid — restoring previous /etc/nginx" >&2; rsync -a --delete "$backup/nginx/" /etc/nginx/; exit 1; }
mkdir -p /var/www/acme
sed -i 's/^\(\s*\)server_tokens build;.*/\1server_tokens off;/' /etc/nginx/nginx.conf
install -m 644 nginx/conf.d/*.conf /etc/nginx/conf.d/
install -m 644 nginx/snippets/*.conf /etc/nginx/snippets/
for f in nginx/sites/*.conf; do
  name="$(basename "$f" .conf)"
  install -m 644 "$f" "/etc/nginx/sites-available/$name"
  ln -sf "/etc/nginx/sites-available/$name" "/etc/nginx/sites-enabled/$name"
done
# Pre-/opt/infra files this layout replaces.
rm -f /etc/nginx/conf.d/wordchain.conf /etc/nginx/sites-enabled/default
/opt/infra/bin/arvan-ips-refresh >/dev/null 2>&1 || echo "warning: ArvanCloud range refresh failed; using the shipped snapshot" >&2
nginx -t -q 2>/dev/null || { nginx -t; restore; }
systemctl reload nginx
rm -rf "$backup"
echo "install ok"
