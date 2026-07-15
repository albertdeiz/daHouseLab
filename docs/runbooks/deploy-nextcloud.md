# Runbook: Deploy Nextcloud

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 90 minutes       |
| Risk level      | Medium           |
| Automation      | Manual           |

## Purpose

Deploy Nextcloud (files, calendar, contacts) at `https://cloud.${DOMAIN}` as a three-container
stack: `nextcloud:apache`, PostgreSQL 16, and Redis, in one compose file. When complete, the app
is behind Caddy, the database is reachable **only** on the stack-internal network, user files
live in `${DATA_ROOT}/nextcloud/data`, the database in `${DATA_ROOT}/nextcloud/db`, application
config in `${CONFIG_ROOT}/nextcloud`, and background jobs run via a dedicated cron container.

## Scope

Covers: the `services/nextcloud/` stack, networks/mounts per the standards, trusted-domain and
proxy-awareness configuration, first admin setup, cron, Caddy site block, monitor. Does not
cover: app-store apps, external storage, LDAP/SSO, or client sync setup.

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] `proxy` network exists: `docker network inspect proxy --format '{{.Name}}'` → `proxy`
- [ ] Caddy deployed and healthy; Uptime Kuma deployed (this deploy will be watched)
- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set
- [ ] ≥ 10 GB free on the data disk to start: `df -h /srv` (user files grow — plan for tens of GB)

## Risks

- Two precious datasets with different failure modes: the Postgres cluster (`db/`) and user files
  (`data/`). Worst case: db and files restored from **different points in time** — Nextcloud's
  file cache desyncs from disk (recoverable with `occ files:scan`, but painful). Back them up as
  a pair.
- Pi 4 constraint: PHP + Postgres + Redis is a heavy stack; first sync of a large photo library
  can saturate I/O and starve other services.
- A wrong `trusted_domains` value locks every user out of the web UI (fixable via `occ`).

## Safety checks

- [ ] `cloud.${DOMAIN}` not already routed: `grep -n "cloud\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Memory headroom: `free -h` → ≥ 2 GB available before starting the stack
- [ ] Uptime Kuma green across the board — do not deploy onto a degraded platform

## Procedure

1. **Create the service directory and host directories**

   ```bash
   cp -r /opt/dahouselab/templates/service /opt/dahouselab/services/nextcloud
   source /opt/dahouselab/.env
   sudo mkdir -p ${CONFIG_ROOT}/nextcloud ${DATA_ROOT}/nextcloud/{db,data}
   sudo chown -R ${PUID}:${PGID} ${CONFIG_ROOT}/nextcloud ${DATA_ROOT}/nextcloud
   sudo chown -R 33:33 ${DATA_ROOT}/nextcloud/data        # www-data inside the container
   ```

   Expected: config and data trees exist. `data/` is owned by UID 33 (`www-data`) — the
   Nextcloud image runs Apache as www-data and refuses a data dir it cannot own.

2. **Write `services/nextcloud/compose.yaml`** — db and redis on `nextcloud_internal` only:

   ```yaml
   name: nextcloud

   services:
     nextcloud:
       image: nextcloud:31.0.6-apache # pinned at time of writing (2026-07)
       container_name: nextcloud
       restart: unless-stopped
       env_file: .env
       environment:
         TZ: ${TZ}
         POSTGRES_HOST: nextcloud-db
         POSTGRES_DB: ${NEXTCLOUD_DB_NAME}
         POSTGRES_USER: ${NEXTCLOUD_DB_USER}
         POSTGRES_PASSWORD: ${NEXTCLOUD_DB_PASSWORD}
         REDIS_HOST: nextcloud-redis
         NEXTCLOUD_TRUSTED_DOMAINS: cloud.${DOMAIN}
         OVERWRITEPROTOCOL: https
         OVERWRITECLIURL: https://cloud.${DOMAIN}
         TRUSTED_PROXIES: 172.16.0.0/12 # docker networks — Caddy's source range
       volumes:
         - ${CONFIG_ROOT}/nextcloud:/var/www/html # app + config.php (small, precious)
         - ${DATA_ROOT}/nextcloud/data:/var/www/html/data # user files (large, precious)
       networks:
         - proxy
         - nextcloud_internal
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "curl", "-fsS", "http://localhost/status.php"]
         interval: 30s
         timeout: 10s
         retries: 3
         start_period: 120s # first boot installs the app tree
       labels:
         dahouselab.service: "nextcloud"
         dahouselab.category: "productivity"
         dahouselab.description: "Files, calendar, contacts"
         dahouselab.url: "https://cloud.${DOMAIN}"
         dahouselab.backup: "true"
       depends_on:
         nextcloud-db:
           condition: service_healthy
         nextcloud-redis:
           condition: service_healthy

     nextcloud-cron:
       image: nextcloud:31.0.6-apache # same image + version as the app, always
       container_name: nextcloud-cron
       restart: unless-stopped
       entrypoint: /cron.sh
       env_file: .env
       environment:
         TZ: ${TZ}
       volumes:
         - ${CONFIG_ROOT}/nextcloud:/var/www/html
         - ${DATA_ROOT}/nextcloud/data:/var/www/html/data
       networks:
         - nextcloud_internal # no web UI — never on proxy
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "pgrep", "-f", "busybox crond"]
         interval: 30s
         timeout: 5s
         retries: 3
       labels:
         dahouselab.service: "nextcloud"
         dahouselab.category: "productivity"
         dahouselab.description: "Nextcloud background jobs"
         dahouselab.backup: "false" # shares the app mounts; nothing unique
       depends_on:
         nextcloud-db:
           condition: service_healthy

     nextcloud-db:
       image: postgres:16.9 # pinned at time of writing (2026-07)
       container_name: nextcloud-db
       restart: unless-stopped
       env_file: .env
       environment:
         TZ: ${TZ}
         POSTGRES_DB: ${NEXTCLOUD_DB_NAME}
         POSTGRES_USER: ${NEXTCLOUD_DB_USER}
         POSTGRES_PASSWORD: ${NEXTCLOUD_DB_PASSWORD}
       volumes:
         - ${DATA_ROOT}/nextcloud/db:/var/lib/postgresql/data
       networks:
         - nextcloud_internal # databases never on the proxy network
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U ${NEXTCLOUD_DB_USER} -d ${NEXTCLOUD_DB_NAME}"]
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 30s
       labels:
         dahouselab.service: "nextcloud"
         dahouselab.category: "productivity"
         dahouselab.description: "Nextcloud PostgreSQL database"
         dahouselab.backup: "true"

     nextcloud-redis:
       image: redis:7.4-alpine # pinned at time of writing (2026-07)
       container_name: nextcloud-redis
       restart: unless-stopped
       environment:
         TZ: ${TZ}
       networks:
         - nextcloud_internal
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "redis-cli", "ping"]
         interval: 30s
         timeout: 5s
         retries: 3
       labels:
         dahouselab.service: "nextcloud"
         dahouselab.category: "productivity"
         dahouselab.description: "Nextcloud cache/locking"
         dahouselab.backup: "false" # pure cache — rebuilt on start

   networks:
     proxy:
       external: true
     nextcloud_internal: {}
   ```

3. **Create `.env`** (mode 600) — globals plus:

   ```bash
   cd /opt/dahouselab/services/nextcloud
   cp /opt/dahouselab/.env .env && chmod 600 .env
   ```

   Append with an editor:

   ```bash
   # --- nextcloud ---
   NEXTCLOUD_DB_NAME=nextcloud
   NEXTCLOUD_DB_USER=nextcloud
   NEXTCLOUD_DB_PASSWORD=   # Generate: openssl rand -base64 32
   ```

   Expected: password filled from `openssl rand -base64 32`; `.env.example` mirrors the names.

4. **Validate and start**

   ```bash
   docker compose config --quiet && echo OK
   docker compose up -d && watch docker compose ps
   ```

   Expected: `OK`; db and redis healthy first, then `nextcloud` healthy (first boot copies the
   app tree into `${CONFIG_ROOT}/nextcloud` — allow several minutes on the Pi).

5. **Add the Caddy site block** to `/opt/dahouselab/infrastructure/configs/Caddyfile` —
   Nextcloud wants the caldav/carddav redirects at the proxy:

   ```text
   cloud.{$DOMAIN} {
   	redir /.well-known/carddav /remote.php/dav 301
   	redir /.well-known/caldav /remote.php/dav 301
   	reverse_proxy nextcloud:80
   }
   ```

   Validate + reload per [deploy-caddy](deploy-caddy.md) step 7; commit. Expected: reload exits 0.

6. **First admin setup** — open `https://cloud.${DOMAIN}`, create the admin account (db fields
   are pre-filled from env). Then confirm background jobs use cron: Settings → Administration →
   Basic settings → Background jobs → **Cron**.

   Expected: dashboard loads; no setup warnings about database.

7. **Verify occ and finish hardening** — `occ` runs as `www-data` inside the app container:

   ```bash
   docker compose exec -u www-data nextcloud php occ status
   docker compose exec -u www-data nextcloud php occ config:system:get trusted_domains
   docker compose exec -u www-data nextcloud php occ maintenance:repair --include-expensive
   ```

   Expected: `installed: true`, version 31.x; trusted domains list `cloud.<domain>`; repair
   completes. (Reference: `occ maintenance:mode --on|--off` is the switch used by backup/update
   runbooks.)

8. **Monitor and inventory** — add an Uptime Kuma HTTP(s) monitor for
   `https://cloud.${DOMAIN}/status.php` (keyword `"installed":true`); update
   [`services/README.md`](../../services/README.md) and Homepage; commit the service dir.

## Verification

- [ ] `docker compose ps` → all four containers `healthy`
- [ ] `curl -sk https://cloud.${DOMAIN}/status.php` → JSON with `"installed":true`
- [ ] Login works; upload a test file, then confirm it landed on the host under `${DATA_ROOT}/nextcloud/data/<admin>/files/`
- [ ] CalDAV redirect works: `curl -sk -o /dev/null -w '%{http_code}\n' https://cloud.${DOMAIN}/.well-known/caldav` → `301`
- [ ] Admin overview (Settings → Overview) shows no proxy/HTTPS warnings
- [ ] Cron ran: Basic settings shows "Last job execution ran ... minutes ago"
- [ ] `docker network inspect proxy` does **not** list `nextcloud-db` or `nextcloud-redis`

## Rollback

```bash
cd /opt/dahouselab/services/nextcloud
docker compose down
```

Remove the site block, reload Caddy. `${CONFIG_ROOT}/nextcloud` and `${DATA_ROOT}/nextcloud`
persist; a later `up -d` resumes the installed instance. If config or db were mutated during
troubleshooting, restore **db and data together** from `${BACKUP_ROOT}` per
[restore-from-backup](restore-from-backup.md), then run
`docker compose exec -u www-data nextcloud php occ files:scan --all` to resync. Rollback possible
at every step; the only point of no return is deleting the data/db trees, which no step here does.

## Troubleshooting

| Symptom                                  | Likely cause                            | Action                                                        |
| ---------------------------------------- | --------------------------------------- | -------------------------------------------------------------- |
| "Access through untrusted domain"        | `trusted_domains` wrong                 | `occ config:system:set trusted_domains 1 --value=cloud.<domain>` |
| Endless redirect / mixed content         | Proxy headers not trusted               | Check `OVERWRITEPROTOCOL`, `TRUSTED_PROXIES` match Caddy's network |
| `nextcloud` unhealthy on first boot      | App-tree copy still running on slow I/O | Wait out `start_period`; `docker compose logs -f nextcloud`    |
| "Data directory readable by other users" | Wrong ownership/permissions on `data/`  | `chown -R 33:33` and `chmod 750` on `${DATA_ROOT}/nextcloud/data` |
| Files on disk missing in UI              | Cache desync (restore, manual copy)     | `occ files:scan --all`                                         |
| DB connection refused at install         | db not healthy yet / wrong password     | `docker compose logs nextcloud-db`; confirm `.env` values      |

## Automation opportunities

- Steps 1–4 are the generic deploy flow — `scripts/deploy-service.sh` candidate.
- Backup pre-hook: `occ maintenance:mode --on` + `pg_dump` + files rsync + `--off` should be
  encoded in the backup tooling rather than remembered.
- A post-deploy `occ`-based smoke test (status, trusted_domains, cron freshness) is scriptable today.

## Future improvements

- Version-control PHP `memory_limit`/opcache tuning for Pi-class hardware once measured under load.
- Evaluate `nextcloud:fpm` + Caddy serving static assets if Apache proves heavy on the Pi.
- Office documents (Collabora) deliberately deferred to the Mini PC ([roadmap](../roadmap/README.md)).
