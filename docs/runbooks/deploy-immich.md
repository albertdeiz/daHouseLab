# Runbook: Deploy Immich

| Field           | Value            |
| --------------- | ---------------- |
| Last reviewed   | 2026-07-17       |
| Estimated time  | 90 minutes       |
| Risk level      | Medium           |
| Automation      | Manual           |

## Purpose

Deploy [Immich](https://immich.app) (photo/video library with mobile backup) at
`https://photos.${DOMAIN}` as a four-container stack: `immich-server`,
`immich-machine-learning`, Postgres (upstream's pgvector/VectorChord image — a hard requirement),
and Valkey (Redis-compatible). When complete: uploads land in `${DATA_ROOT}/immich/upload`, the
database in `${DATA_ROOT}/immich/db`, the app is behind Caddy, and ML load is constrained to
what a Pi 4 survives.

## Scope

Covers: the `services/immich/` stack, version pinning discipline, storage layout, Pi-4 ML
tuning, Caddy site block, first admin setup, monitor. Does not cover: mobile app enrollment,
external libraries, or hardware transcoding (not available on this platform).

**Version discipline:** Immich moves fast and its migrations are one-way. Pin the exact image
tag directly in `compose.yaml` (per the version-pinned-images rule — no floating `IMMICH_VERSION`
variable) — **never `:release`** — and change it only via [update-containers](update-containers.md)
after reading that version's release notes (breaking changes are routine; the db image tag must
move together with the server/ML tag).

## Prerequisites

- [ ] [deploy-with-compose](deploy-with-compose.md) read — this runbook assumes that generic procedure
- [ ] `proxy` network exists; Caddy deployed and healthy; Uptime Kuma deployed (deploy is watched)
- [ ] Root `.env` at `/opt/dahouselab/.env` defines the global set
- [ ] Disk budget confirmed: photos are the largest dataset on the platform — `df -h /srv` shows
  enough for your library plus growth
- [ ] **Storage readiness (hard blocker):** `${DATA_ROOT}` (`/srv`) lives on an **SSD**, not the
  SD card, and `/mnt/backups` has capacity for the library — see
  [disk-inventory](../storage/disk-inventory.md). A photo library on the SD card violates
  [ADR-0005](../decisions/0005-raspberry-pi-platform.md) (SD endurance/corruption) and would be
  unbacked, defeating the single-node recoverability guarantee. **As of 2026-07-17 this is NOT
  met** (data still on the 32 GB SD, backup target an 8 GB pendrive) — resolve via
  [configure-usb-boot](configure-usb-boot.md) + a real backup disk before deploying.
- [ ] Read the release notes for the version being pinned:
  <https://github.com/immich-app/immich/releases>

## Risks

- Worst case: irreplaceable photos exist **only** in Immich and `${DATA_ROOT}/immich` is lost —
  keep originals elsewhere until [validate-backup](validate-backup.md) has proven restores
  include `upload/` and `db/` (they must be backed up as a pair, like Nextcloud).
- ML (face/CLIP models) can OOM or I/O-starve a Pi 4 with 8 GB shared across the whole
  platform. Mitigations are built into the compose below; the safe fallback is disabling the ML
  container entirely until the Mini PC migration.
- Upgrading by floating tag would apply surprise schema migrations — hence the pin rule above.

## Safety checks

- [ ] `photos.${DOMAIN}` not already routed: `grep -n "photos\." /opt/dahouselab/infrastructure/configs/Caddyfile` → no output
- [ ] Memory headroom before start: `free -h` → ≥ 3 GB available (server + ML + db peak together)
- [ ] Uptime Kuma green across the board

## Procedure

1. **Create the service directory and host directories**

   ```bash
   cp -r /opt/dahouselab/templates/service /opt/dahouselab/services/immich
   source /opt/dahouselab/.env
   sudo mkdir -p ${DATA_ROOT}/immich/{upload,db} ${CONFIG_ROOT}/immich
   sudo chown -R ${PUID}:${PGID} ${DATA_ROOT}/immich ${CONFIG_ROOT}/immich
   ```

   Expected: `/srv/dahouselab/data/immich/{upload,db}` and config dir exist, `PUID:PGID`.

2. **Write `services/immich/compose.yaml`** — adapted from upstream's release compose to this
   platform's conventions (db/cache on `immich_internal` only, bind mounts, no `ports:`):

   ```yaml
   name: immich

   services:
     immich-server:
       image: ghcr.io/immich-app/immich-server:v1.137.3 # pinned (2026-07); bump only via update-containers
       container_name: immich-server
       restart: unless-stopped
       env_file:
         - .env          # platform globals (via symlink)
         - .env.service  # service-specific — overrides globals on collision
       environment:
         TZ: ${TZ}
         # DB_USERNAME/DB_PASSWORD/DB_DATABASE_NAME arrive from .env.service via
         # env_file — env_file is NOT a compose interpolation source, so
         # ${IMMICH_DB_*} would resolve to blank strings. Hostnames are fixed
         # infra values, kept as literals here.
         DB_HOSTNAME: immich-db
         REDIS_HOSTNAME: immich-redis
       volumes:
         - ${DATA_ROOT}/immich/upload:/usr/src/app/upload # originals + thumbs + encoded
         - /etc/localtime:/etc/localtime:ro
       networks:
         - proxy
         - immich_internal
       security_opt:
         - no-new-privileges:true
       # Healthcheck is baked into the upstream image (documented deviation from
       # rule 8 — the image's own check is authoritative across version changes).
       labels:
         dahouselab.service: "immich"
         dahouselab.category: "media"
         dahouselab.description: "Photo and video library"
         dahouselab.url: "https://photos.${DOMAIN}"
         dahouselab.backup: "true"
       depends_on:
         immich-db:
           condition: service_healthy
         immich-redis:
           condition: service_healthy

     immich-machine-learning:
       image: ghcr.io/immich-app/immich-machine-learning:v1.137.3 # must match immich-server, always
       container_name: immich-machine-learning
       restart: unless-stopped
       env_file:
         - .env          # platform globals (via symlink)
         - .env.service  # service-specific — overrides globals on collision
       environment:
         TZ: ${TZ}
         MACHINE_LEARNING_WORKERS: "1" # Pi 4: never more than one model worker
       volumes:
         - ${CONFIG_ROOT}/immich/model-cache:/cache # downloaded models — re-downloadable
       networks:
         - immich_internal # no web UI — never on proxy
       security_opt:
         - no-new-privileges:true
       deploy:
         resources:
           limits:
             memory: 2g # hard cap so ML cannot OOM the platform
       labels:
         dahouselab.service: "immich"
         dahouselab.category: "media"
         dahouselab.description: "Immich ML (faces, smart search)"
         dahouselab.backup: "false" # model cache is re-downloadable

     immich-db:
       # Upstream REQUIRES its own Postgres image with vector extensions —
       # a stock postgres image will not work. This tag must match the release
       # notes for the pinned immich-server tag, and move together with it.
       image: ghcr.io/immich-app/postgres:16-vectorchord0.4.3 # pinned at time of writing (2026-07)
       container_name: immich-db
       restart: unless-stopped
       env_file:
         - .env          # platform globals (via symlink)
         - .env.service  # service-specific — overrides globals on collision
       environment:
         TZ: ${TZ}
         # POSTGRES_DB/USER/PASSWORD arrive from .env.service via env_file.
       volumes:
         - ${DATA_ROOT}/immich/db:/var/lib/postgresql/data
       networks:
         - immich_internal # databases never on the proxy network
       security_opt:
         - no-new-privileges:true
       healthcheck:
         # $$ escapes compose interpolation; the container shell expands these
         # from env_file at runtime (no host-side .env.service value needed).
         test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
         interval: 30s
         timeout: 5s
         retries: 3
         start_period: 30s
       labels:
         dahouselab.service: "immich"
         dahouselab.category: "media"
         dahouselab.description: "Immich PostgreSQL (vector) database"
         dahouselab.backup: "true"

     immich-redis:
       image: valkey/valkey:8.1-alpine # pinned at time of writing (2026-07); upstream's choice
       container_name: immich-redis
       restart: unless-stopped
       environment:
         TZ: ${TZ}
       networks:
         - immich_internal
       security_opt:
         - no-new-privileges:true
       healthcheck:
         test: ["CMD", "valkey-cli", "ping"]
         interval: 30s
         timeout: 5s
         retries: 3
       labels:
         dahouselab.service: "immich"
         dahouselab.category: "media"
         dahouselab.description: "Immich job queue/cache"
         dahouselab.backup: "false"

   networks:
     proxy:
       external: true
     immich_internal: {}
   ```

3. **Create the environment files** ([ADR-0012](../decisions/0012-layered-environment-files.md)) —
   globals via the `.env` symlink, service variables in `.env.service` (mode 600):

   ```bash
   cd /opt/dahouselab/services/immich
   ln -sf ../../.env .env
   cp .env.service.example .env.service && chmod 600 .env.service
   ```

   Fill `.env.service` with an editor:

   ```bash
   # --- immich database ---
   # Container-native names, passed straight through via env_file (compose does
   # NOT interpolate them). immich-server reads the DB_* names; the Postgres
   # image reads the POSTGRES_* names — the three shared values (user, password,
   # db name) MUST be identical across both schemes or the server can't connect.
   DB_USERNAME=immich
   DB_PASSWORD=            # Generate: openssl rand -base64 32
   DB_DATABASE_NAME=immich
   POSTGRES_USER=immich        # = DB_USERNAME
   POSTGRES_PASSWORD=          # = DB_PASSWORD
   POSTGRES_DB=immich          # = DB_DATABASE_NAME
   ```

   The image tag is pinned in `compose.yaml` (no `IMMICH_VERSION` var — it is used in the
   `image:` field, which env_file cannot populate). Expected: `.env.service` filled, `-rw-------`,
   and `ls -l` shows `.env -> ../../.env`; `.env.service.example` mirrors names with the passwords empty.

4. **Validate and start**

   ```bash
   docker compose config --quiet && echo OK
   docker compose up -d && watch docker compose ps
   ```

   Expected: `OK`; db/redis healthy, then `immich-server` healthy (first boot runs migrations;
   ML additionally downloads models on first job — hundreds of MB).

5. **Add the Caddy site block** — Immich needs large uploads allowed through the proxy:

   ```text
   photos.{$DOMAIN} {
   	request_body {
   		max_size 5GB
   	}
   	reverse_proxy immich-server:2283
   }
   ```

   Validate + reload per [deploy-caddy](deploy-caddy.md) step 7; commit. Expected: reload exits 0.

6. **First admin setup** — open `https://photos.${DOMAIN}`, create the admin account, set
   storage template if desired **before** first uploads (changing it later reorganizes files).

   Expected: dashboard loads; upload of a test photo succeeds.

7. **Constrain ML for the Pi 4** — in the web UI: Administration → Settings → Job settings →
   set Smart Search and Face Detection **concurrency to 1**; consider pausing those jobs during
   initial bulk import and running them overnight. If the Pi still struggles, disable ML
   entirely (Administration → Settings → Machine Learning → disable, or `docker compose stop
   immich-machine-learning`) until the Mini PC migration ([roadmap](../roadmap/README.md)) —
   uploads and browsing work fine without ML.

   Expected: job concurrency saved; `free -h` stays > 1 GB available during a test import.

8. **Monitor and inventory** — Uptime Kuma HTTP(s) monitor on
   `https://photos.${DOMAIN}/api/server/ping` (expects `{"res":"pong"}`); update
   [`services/README.md`](../../services/README.md) and Homepage; commit the service dir.

## Verification

- [ ] `docker compose ps` → all four containers `healthy` (ML may show `running` while models download)
- [ ] `curl -sk https://photos.${DOMAIN}/api/server/ping` → `{"res":"pong"}`
- [ ] Test photo visible in the web UI, and the original landed under `${DATA_ROOT}/immich/upload/`
- [ ] `docker network inspect proxy` lists only `immich-server` from this stack
- [ ] During a test import, platform stays responsive and no container is OOM-killed (`docker events --filter event=oom` quiet)

## Rollback

```bash
cd /opt/dahouselab/services/immich
docker compose down
```

Remove the site block, reload Caddy. `${DATA_ROOT}/immich` persists; `up -d` with the **same
pinned image tag** resumes cleanly. If a version change was attempted and migrations ran,
rolling back the tag is **not** supported — restore `db/` and `upload/` together from
`${BACKUP_ROOT}` per [restore-from-backup](restore-from-backup.md). Mark that boundary clearly
whenever this runbook is reused for upgrades.

## Troubleshooting

| Symptom                                | Likely cause                                | Action                                                     |
| --------------------------------------- | ------------------------------------------- | ----------------------------------------------------------- |
| Server crash-loops on start             | Wrong db image/tag for this Immich version  | Match db image tag to the release notes for the pinned immich-server tag |
| Uploads fail at ~1 GB+                  | Proxy body limit                            | Confirm `request_body max_size` in the site block          |
| Pi unresponsive during import           | ML jobs at default concurrency              | Step 7: concurrency 1, pause jobs, or stop the ML container |
| ML container OOM-killed                 | Model too large for the 2 GB cap            | Keep ML disabled on Pi 4; revisit on Mini PC                |
| Mobile app cannot connect               | Wrong server URL/cert not trusted on phone  | Use `https://photos.<domain>`; fix client CA trust          |
| `pgvector`/vector extension errors      | Stock postgres image was substituted        | Use `ghcr.io/immich-app/postgres` only                      |

## Automation opportunities

- Steps 1–4 are the generic deploy flow — `scripts/deploy-service.sh` candidate.
- A version-bump helper that diffs upstream release notes and the pinned db image would
  de-risk updates; blocked on parsing release metadata reliably.
- Backup pre-hook: `pg_dump` of `immich-db` before file backup, as with Nextcloud.

## Future improvements

- Re-enable full ML after the Mini PC migration; benchmark first.
- Consider `${DATA_ROOT}/shares/photos` read-only external library for pre-existing archives.
