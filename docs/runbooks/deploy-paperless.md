# Runbook: Deploy Paperless-ngx

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-14       |
| Estimated time  | 60 minutes       |
| Risk level      | Medium           |
| Automation      | Manual           |

## Purpose

Deploy [paperless-ngx](https://docs.paperless-ngx.com) (document management with OCR) at
`https://paperless.${DOMAIN}` as a three-container stack: the paperless-ngx webserver,
PostgreSQL 16, and Redis (task broker). When complete: documents dropped into the consume
directory are OCR'd and archived, all document data lives under `${DATA_ROOT}/paperless-ngx`,
the database is on the stack-internal network only, and the app is behind Caddy.

Note on naming: this runbook is `deploy-paperless.md` (verb-object, common name), but the
service directory is `services/paperless-ngx/` — matching the upstream project name and the
`dahouselab.service` label.

## Scope

Covers: the `services/paperless-ngx/` stack, secret generation, storage layout
(data/media/export/consume), CSRF-correct `PAPERLESS_URL`, superuser creation, Caddy site
block, monitor. Does not cover: mail ingestion, Tika/Gotenberg office-document support
(deliberately deferred — heavy on Pi 4), or scanner integration.

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] `proxy` network exists: `docker network inspect proxy --format '{{.Name}}'` → `proxy`
- [ ] Caddy deployed and healthy; Uptime Kuma deployed (deploy is watched)
- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set
- [ ] Disk space: `df -h /srv` — OCR'd archives roughly double the source size; budget accordingly

## Risks

- Worst case: loss of `media/` (original + archived documents) — originals are often shredded
  after ingestion, so this is irreplaceable data. `media/` + `db/` must be backed up as a pair;
  the built-in `document_exporter` (step 9 reference) is the belt-and-braces second format.
- OCR (one worker) can pin a Pi 4 core for minutes per large PDF — expected, not a fault.
- A wrong `PAPERLESS_URL` breaks logins with CSRF errors — it must be the exact external URL.

## Safety checks

- [ ] `paperless.${DOMAIN}` not already routed: `grep -n "paperless\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Memory headroom: `free -h` → ≥ 2 GB available
- [ ] Uptime Kuma green across the board

## Procedure

1. **Create the service directory and host directories**

   ```bash
   cp -r /opt/dahouselab/templates/service /opt/dahouselab/services/paperless-ngx
   source /opt/dahouselab/.env
   sudo mkdir -p ${DATA_ROOT}/paperless-ngx/{data,media,export,consume,db}
   sudo chown -R ${PUID}:${PGID} ${DATA_ROOT}/paperless-ngx
   ```

   Expected: five directories under `/srv/dahouselab/data/paperless-ngx`, owned `PUID:PGID`.
   (`data/` is the app's index/state — data, not config, hence under `DATA_ROOT`.)

2. **Write `services/paperless-ngx/compose.yaml`**

   ```yaml
   name: paperless-ngx

   services:
     webserver:
       image: ghcr.io/paperless-ngx/paperless-ngx:2.17.1 # pinned at time of writing (2026-07)
       container_name: paperless-ngx
       restart: unless-stopped
       env_file: .env
       environment:
         TZ: ${TZ}
         USERMAP_UID: ${PUID}
         USERMAP_GID: ${PGID}
         PAPERLESS_TIME_ZONE: ${TZ}
         PAPERLESS_REDIS: redis://paperless-redis:6379
         PAPERLESS_DBHOST: paperless-db
         PAPERLESS_DBNAME: ${PAPERLESS_DB_NAME}
         PAPERLESS_DBUSER: ${PAPERLESS_DB_USER}
         PAPERLESS_DBPASS: ${PAPERLESS_DB_PASSWORD}
         PAPERLESS_SECRET_KEY: ${PAPERLESS_SECRET_KEY}
         PAPERLESS_URL: https://paperless.${DOMAIN} # exact external URL — CSRF trust
         PAPERLESS_OCR_LANGUAGE: eng+spa
         PAPERLESS_TASK_WORKERS: "1" # Pi 4: one OCR worker
       volumes:
         - ${DATA_ROOT}/paperless-ngx/data:/usr/src/paperless/data
         - ${DATA_ROOT}/paperless-ngx/media:/usr/src/paperless/media
         - ${DATA_ROOT}/paperless-ngx/export:/usr/src/paperless/export
         - ${DATA_ROOT}/paperless-ngx/consume:/usr/src/paperless/consume
       networks:
         - proxy
         - paperless_internal
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "curl", "-fsS", "--max-time", "2", "http://localhost:8000"]
         interval: 30s
         timeout: 10s
         retries: 3
         start_period: 120s # first boot runs migrations + builds search index
       labels:
         dahouselab.service: "paperless-ngx"
         dahouselab.category: "productivity"
         dahouselab.description: "Document management with OCR"
         dahouselab.url: "https://paperless.${DOMAIN}"
         dahouselab.backup: "true"
       depends_on:
         paperless-db:
           condition: service_healthy
         paperless-redis:
           condition: service_healthy

     paperless-db:
       image: postgres:16.9 # pinned at time of writing (2026-07)
       container_name: paperless-db
       restart: unless-stopped
       env_file: .env
       environment:
         TZ: ${TZ}
         POSTGRES_DB: ${PAPERLESS_DB_NAME}
         POSTGRES_USER: ${PAPERLESS_DB_USER}
         POSTGRES_PASSWORD: ${PAPERLESS_DB_PASSWORD}
       volumes:
         - ${DATA_ROOT}/paperless-ngx/db:/var/lib/postgresql/data
       networks:
         - paperless_internal # databases never on the proxy network
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U ${PAPERLESS_DB_USER} -d ${PAPERLESS_DB_NAME}"]
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 30s
       labels:
         dahouselab.service: "paperless-ngx"
         dahouselab.category: "productivity"
         dahouselab.description: "Paperless PostgreSQL database"
         dahouselab.backup: "true"

     paperless-redis:
       image: redis:7.4-alpine # pinned at time of writing (2026-07)
       container_name: paperless-redis
       restart: unless-stopped
       environment:
         TZ: ${TZ}
       networks:
         - paperless_internal
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "redis-cli", "ping"]
         interval: 30s
         timeout: 5s
         retries: 3
       labels:
         dahouselab.service: "paperless-ngx"
         dahouselab.category: "productivity"
         dahouselab.description: "Paperless task broker"
         dahouselab.backup: "false" # queue only — safely rebuilt

   networks:
     proxy:
       external: true
     paperless_internal: {}
   ```

3. **Create `.env`** (mode 600) — globals plus paperless variables:

   ```bash
   cd /opt/dahouselab/services/paperless-ngx
   cp /opt/dahouselab/.env .env && chmod 600 .env
   ```

   Generate the secret key, then append with an editor:

   ```bash
   openssl rand -base64 48   # PAPERLESS_SECRET_KEY — signs sessions; rotation logs everyone out
   openssl rand -base64 32   # PAPERLESS_DB_PASSWORD
   ```

   ```bash
   # --- paperless-ngx ---
   PAPERLESS_DB_NAME=paperless
   PAPERLESS_DB_USER=paperless
   PAPERLESS_DB_PASSWORD=    # Generate: openssl rand -base64 32
   PAPERLESS_SECRET_KEY=     # Generate: openssl rand -base64 48
   ```

   Expected: both secrets filled; `.env.example` mirrors names with empty values.

4. **Validate and start**

   ```bash
   docker compose config --quiet && echo OK
   docker compose up -d && watch docker compose ps
   ```

   Expected: `OK`; db/redis healthy first, then `paperless-ngx` healthy (allow the full
   `start_period` — migrations on Pi-class I/O are slow).

5. **Create the superuser**

   ```bash
   docker compose run --rm webserver createsuperuser
   ```

   Expected: interactive prompt; account created. (Non-interactive alternative:
   `PAPERLESS_ADMIN_USER`/`PAPERLESS_ADMIN_PASSWORD` env vars on first boot — avoided here
   because that puts a credential in `.env` permanently; the interactive path leaves nothing
   behind.)

6. **Add the Caddy site block** — allow large scans through the proxy:

   ```text
   paperless.{$DOMAIN} {
   	request_body {
   		max_size 200MB
   	}
   	reverse_proxy paperless-ngx:8000
   }
   ```

   Validate + reload per [deploy-caddy](deploy-caddy.md) step 7; commit. Expected: reload exits 0.

7. **Verify login and first ingestion** — open `https://paperless.${DOMAIN}`, log in as the
   superuser, then feed the consumer a test document:

   ```bash
   cp /usr/share/doc/shared-mime-info/shared-mime-info-spec.pdf 2>/dev/null \
     ${DATA_ROOT}/paperless-ngx/consume/ || echo "use any PDF you have at hand"
   ```

   Expected: within a couple of minutes the document appears in the UI, OCR'd and searchable,
   and the file has been **moved out of** `consume/` into `media/`.

8. **Monitor and inventory** — Uptime Kuma HTTP(s) monitor on `https://paperless.${DOMAIN}`
   (expect `200`; the login page suffices). Update
   [`services/README.md`](../../services/README.md) and Homepage; commit the service dir.

9. **Note the export path for backups** — the platform backup must include `media/`, `data/`
   and a db dump; additionally schedule
   `docker compose exec webserver document_exporter ../export` periodically — it writes a
   portable, tool-independent copy of every document into `${DATA_ROOT}/paperless-ngx/export`.

   Expected: noted in the backup configuration ([execute-backup](execute-backup.md)).

## Verification

- [ ] `docker compose ps` → all three containers `healthy`
- [ ] `curl -sk -o /dev/null -w '%{http_code}\n' https://paperless.${DOMAIN}` → `200`
- [ ] Superuser login works over HTTPS; no CSRF error on login (proves `PAPERLESS_URL`)
- [ ] Test document ingested (step 7) and present under `${DATA_ROOT}/paperless-ngx/media/documents/`
- [ ] `docker network inspect proxy` lists only `paperless-ngx` from this stack
- [ ] Uptime Kuma monitor green; platform overall healthy

## Rollback

```bash
cd /opt/dahouselab/services/paperless-ngx
docker compose down
```

Remove the site block, reload Caddy. All five data directories persist; `up -d` resumes the
installed instance. If db or media were mutated during troubleshooting, restore them **as a
pair** from `${BACKUP_ROOT}` per [restore-from-backup](restore-from-backup.md), or re-import
from the `export/` tree with `document_importer`. Restore `.env` from backup if edited.
Rollback possible at every step.

## Troubleshooting

| Symptom                                | Likely cause                             | Action                                                     |
| --------------------------------------- | ---------------------------------------- | ----------------------------------------------------------- |
| CSRF failure on login                   | `PAPERLESS_URL` missing/mismatched       | Set exact external URL incl. scheme; `docker compose up -d` |
| Documents stuck in `consume/`           | Ownership not `PUID:PGID` / consumer dead| `chown` the dir; `docker compose logs webserver`            |
| OCR gibberish for non-English docs      | `PAPERLESS_OCR_LANGUAGE` wrong           | Set correct `eng+<lang>` codes; re-run OCR on the document  |
| Very slow ingestion, high load          | Expected on Pi 4 (1 worker)              | Accept, or queue documents off-hours; Mini PC will fix      |
| `permission denied` in container logs   | `USERMAP_UID/GID` mismatch with host dirs| Align env with `PUID:PGID`; re-chown; recreate container    |
| 502 from Caddy                          | Wrong upstream (must be `paperless-ngx:8000`) | Fix site block; reload                                 |

## Automation opportunities

- Steps 1–4 are the generic deploy flow — `scripts/deploy-service.sh` candidate.
- The `document_exporter` run (step 9) should become a scheduled job in the backup tooling;
  nothing blocks it today.
- A post-deploy smoke test (drop fixture PDF → poll API until indexed) is scriptable via the
  Paperless REST API with a token.

## Future improvements

- Enable Tika + Gotenberg for office formats after the Mini PC migration.
- Mail-in ingestion (`PAPERLESS_CONSUMER` mail rules) once an internal mail path exists.
- Pre-consume script for deskewing/splitting scanner batches.
