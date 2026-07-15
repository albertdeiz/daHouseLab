# Runbook: Restore from backup

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 30–90 minutes per service                    |
| Risk level      | High                                         |
| Automation      | Manual — target home: `scripts/restore/`     |

## Purpose

Return one service — or the whole platform — to the state captured in a chosen backup set:
config and data restored from `${BACKUP_ROOT}`, database rebuilt from its native dump into a
fresh database container, ownership fixed, service verified healthy. On success the service
runs with backup-set data and the pre-restore (broken) state is preserved aside for forensics.

## Scope

Covers: restoring any single service's config, data, and database, and the all-services loop.
Does not cover: rebuilding the host or Docker ([disaster-recovery](disaster-recovery.md) chains
into this runbook for that), or fixing whatever broke the service in the first place — restore
replaces state, it does not remove causes. Non-production rehearsal is
[validate-backup](validate-backup.md).

## Prerequisites

- [ ] The failure is understood well enough to know restore is the right tool (not, e.g., a
      config typo fixable in place)
- [ ] Backup disk mounted: `findmnt --target /mnt/backups`
- [ ] The chosen set passed validation, or validate its checksums now:
      `sudo sha256sum -c /mnt/backups/dahouselab/latest/SHA256SUMS`
- [ ] Enough free space on the data disk for a side-by-side snapshot: `df -h /srv/dahouselab`
- [ ] Global env loadable: `test -f /opt/dahouselab/.env && echo OK`

## Risks

Worst case: restoring on top of the only remaining copy of newer-than-backup data, destroying
it. Everything created after the backup (RPO) is lost by design — but the snapshot-aside step
guarantees the pre-restore state survives on disk. **Never run `rsync --delete` toward
production paths before the snapshot step is done.** Restoring a DB dump into a dirty data
directory is the second classic failure — always into a fresh, empty database directory.
When in doubt about a set's quality, restore to a staging path first and inspect it
(step 3, alternative), exactly as [validate-backup](validate-backup.md) does.

## Safety checks

- [ ] Identify the exact backup set and write it down in the operations log:

  ```bash
  set -a; source /opt/dahouselab/.env; set +a
  BACKUP_SET=$(readlink -f "${BACKUP_ROOT}/dahouselab/latest")   # or a specific dated set
  SVC=nextcloud                                                  # service being restored
  grep backup_date "${BACKUP_SET}/MANIFEST.txt"
  ```

  Expected: the date you intend to restore to. Everything newer than this is accepted as lost.

- [ ] The set contains this service:

  ```bash
  sudo ls "${BACKUP_SET}/config/${SVC}" "${BACKUP_SET}/data/${SVC}" >/dev/null && echo present
  ```

  Expected: `present`.

## Procedure

1. **Stop the service's stack** so nothing writes during the restore:

   ```bash
   cd /opt/dahouselab/services/${SVC}
   docker compose down
   ```

   Expected: `docker ps --format '{{.Names}}' | grep ${SVC}` returns nothing.

2. **Snapshot the current (broken) state aside.** `mv` on the same filesystem is instant and
   loses nothing:

   ```bash
   TS=$(date +%F-%H%M)
   sudo mv "${CONFIG_ROOT}/${SVC}" "${CONFIG_ROOT}/${SVC}.broken-${TS}"
   sudo mv "${DATA_ROOT}/${SVC}"   "${DATA_ROOT}/${SVC}.broken-${TS}"
   ```

   Expected: both `.broken-*` directories exist; production paths for the service are gone.
   This is the rollback point — do not delete these until verification passes and you are done.

3. **Restore config and data from the backup set** into the now-vacant production paths:

   ```bash
   sudo rsync -aHAX "${BACKUP_SET}/config/${SVC}/" "${CONFIG_ROOT}/${SVC}/"
   sudo rsync -aHAX "${BACKUP_SET}/data/${SVC}/"   "${DATA_ROOT}/${SVC}/"
   ```

   Expected: exit 0; trees populated. **When in doubt** about the set, rsync into
   `/srv/dahouselab/staging/restore-${SVC}/` first, inspect, then `mv` into place — never
   experiment directly on the production path.

4. **Prepare a fresh database directory.** For Postgres services, the file-copied
   `data/${SVC}/postgres` (or equivalent) directory from the backup is *not* the source of
   truth — the dump is. Move it aside so the DB container initializes empty:

   ```bash
   sudo mv "${DATA_ROOT}/${SVC}/postgres" "${DATA_ROOT}/${SVC}/postgres.filecopy-${TS}"
   sudo install -d -o 999 -g 999 "${DATA_ROOT}/${SVC}/postgres"
   ```

   Expected: empty `postgres/` directory (owner per the DB image's user; official postgres uses
   999). SQLite services (vaultwarden, uptime-kuma): instead, replace the live DB file with the
   dump — e.g. `sudo cp "${DATA_ROOT}/vaultwarden/db-dumps/<latest>.sqlite3" "${DATA_ROOT}/vaultwarden/db.sqlite3"`
   and remove stale `db.sqlite3-wal`/`-shm` files — then skip to step 6.

5. **Start only the database and restore the dump** into it:

   ```bash
   cd /opt/dahouselab/services/${SVC}
   docker compose up -d postgres          # service name per the stack's compose.yaml
   until docker exec ${SVC}-postgres pg_isready -q; do sleep 2; done
   DUMP=$(sudo ls -t "${DATA_ROOT}/${SVC}/db-dumps/"*.dump | head -n 1)
   sudo cat "${DUMP}" | docker exec -i ${SVC}-postgres \
     pg_restore -U "${POSTGRES_USER:-postgres}" --create --exit-on-error -d postgres
   ```

   Expected: `pg_restore` exits 0. The fresh container creates the role/db from its env vars;
   `--create` recreates the database from the dump. Same Postgres major version as the dump's
   producer is required.

6. **Fix ownership** on the application trees (dumps and rsync preserve backup-time ownership,
   which is normally already correct — this makes it explicit):

   ```bash
   sudo chown -R 1000:1000 "${CONFIG_ROOT}/${SVC}"
   sudo find "${DATA_ROOT}/${SVC}" -path "${DATA_ROOT}/${SVC}/postgres" -prune -o -print0 \
     | sudo xargs -0 chown 1000:1000
   ```

   Expected: app files `PUID:PGID` 1000:1000; the `postgres/` subtree stays owned by the DB
   image's user — do not chown it to 1000.

7. **Start the full stack and watch it come up**

   ```bash
   docker compose up -d
   docker compose ps
   docker compose logs -f --tail=100
   ```

   Expected: all containers reach `(healthy)`; logs show normal startup, no migration errors.

8. **Run the service's verification** — the Verification section of its deploy runbook
   (e.g. [deploy-nextcloud](deploy-nextcloud.md)): log in over HTTPS, open known data (a file,
   a photo, a document), confirm it matches the backup date.

   Expected: the app works and shows backup-time content.

9. **All-services restore:** repeat steps 1–8 per service in dependency order — caddy,
   uptime-kuma, homepage, vaultwarden, nextcloud, immich, paperless-ngx — as indexed in the
   [runbooks README](README.md). Tailscale is host-level config, restored with `${CONFIG_ROOT}`.

## Verification

- [ ] `docker compose ps` for the service — every container `(healthy)`
- [ ] Service URL returns 200 over HTTPS via Caddy: `curl -sSo /dev/null -w '%{http_code}\n' https://<svc>.${DOMAIN}`
- [ ] Data spot-check in the UI matches the backup set's date
- [ ] Platform-wide: [run-health-checks](run-health-checks.md)
- [ ] Operations log entry written: what broke, which set was restored, data-loss window

## Rollback

Up to and including step 3, rollback is: `docker compose down`, `mv` the `.broken-${TS}`
directories back into place, `docker compose up -d` — the broken-but-original state returns
intact. After step 5 the fresh DB exists but the `.broken-*` snapshot still allows the same
rollback. Delete `.broken-*` and `postgres.filecopy-*` directories only after several days of
healthy operation.

## Troubleshooting

| Symptom                                      | Likely cause                            | Action                                                       |
| -------------------------------------------- | --------------------------------------- | ------------------------------------------------------------ |
| `pg_restore: error: database ... exists`     | DB dir not fresh (step 4 skipped)       | Down the DB, redo step 4, restore again                      |
| App loops on "database migration" errors     | Dump older than app image expects       | Pin the app image to the version current at backup date, then update via [update-containers](update-containers.md) |
| Permission denied in app logs                | Ownership wrong after restore           | Re-run step 6; check the compose file's PUID/PGID            |
| Vaultwarden rejects logins after restore     | Stale `-wal`/`-shm` beside restored DB  | Stop stack, delete them, start again                         |
| Caddy 502 for the restored service           | Stack up but not on `proxy` network     | `docker network inspect proxy`; `docker compose up -d` again |
| Restored data older than expected            | `latest` pointed at an old set          | Choose the dated set explicitly in the safety checks         |

## Automation opportunities

`scripts/restore/restore-service.sh <service> [set]`: stop → snapshot-aside → rsync → fresh-DB
→ pg_restore/sqlite swap → chown → up, with the dependency-ordered all-services wrapper as
`scripts/restore/restore-all.sh`. The snapshot-aside and fresh-DB-dir rules belong in the
script as non-optional steps — automation removes the temptation to skip them under stress.

## Future improvements

- Per-service restore notes (occ commands for Nextcloud, immich microservices ordering)
- Scripted RPO report: diff backup date vs now, list what the operator should expect to be lost
- Practice cadence: this runbook is rehearsed quarterly per the [operations rhythm](../operations/README.md)
