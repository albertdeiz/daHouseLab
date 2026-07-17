# Runbook: Execute backup

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 30–60 minutes (first full run: several hours) |
| Risk level      | Low                                          |
| Automation      | Scripted — `scripts/backup/run-backup.sh` (this runbook is its specification; run the script, use this document to understand and verify it) |

## Purpose

Produce a complete, verifiable backup of the platform on the external backup disk
(`${BACKUP_ROOT}`): database dumps taken with native tools, plus an rsync copy of
`${CONFIG_ROOT}` and `${DATA_ROOT}` into a dated, hardlink-rotated backup set with a manifest.
On success, the latest backup set under `${BACKUP_ROOT}/dahouselab/daily/` is complete,
checksummed, and no older than today.

## Scope

Covers: all services with `dahouselab.backup: "true"` — config trees, data trees, and database
dumps (Postgres for nextcloud/immich/paperless-ngx, SQLite for vaultwarden; uptime-kuma v2 uses
an **embedded MariaDB** with no safe hot-copy, so it is stop-copied during the rsync window).
Does not cover: the repository (backed up via Git remotes), container images (re-pullable),
the OS (reproducible via [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md)), or off-site
copy 3 (future — see roadmap). Proving restorability is [validate-backup](validate-backup.md).

## Prerequisites

- [ ] SSH access to the host with sudo
- [ ] The external backup disk is physically attached
- [ ] `sqlite3` installed on the host: `sqlite3 --version`
- [ ] Global env loadable: `test -f /opt/dahouselab/.env && echo OK`
- [ ] Backup policy read: [`docs/backup/README.md`](../backup/README.md)

## Risks

Worst case: the backup silently overwrites the only good previous set with corrupt data, or
runs against an unmounted `/mnt/backups` and fills the root filesystem. Mitigations: refuse to
run unless the backup disk is a distinct mounted device; dated sets mean a bad run never
touches previous sets; retention pruning only deletes sets older than policy. A hot dump taken
during heavy writes can capture app files and DB slightly out of sync (see step 3 notes).

## Safety checks

- [ ] Backup disk is mounted and is not the data disk — **refuse to proceed otherwise**:

  ```bash
  findmnt --target /mnt/backups
  [ "$(findmnt -n -o SOURCE --target /mnt/backups)" != "$(findmnt -n -o SOURCE --target /srv/dahouselab)" ] \
    && echo "OK: separate devices" || echo "ABORT: same device"
  ```

  Expected: a mount line for `/mnt/backups` and `OK: separate devices`.

- [ ] Enough free space on the backup disk (rotation hardlinks mean a run needs roughly the
  size of changed data, not the full tree):

  ```bash
  df -h /mnt/backups /srv/dahouselab
  ```

  Expected: free space on `/mnt/backups` exceeds used space delta; alert threshold is 80% used.

- [ ] All stacks healthy before dumping (a dump of a broken database enshrines the breakage):

  ```bash
  docker ps --format '{{.Names}}\t{{.Status}}' | grep -v '(healthy)' || echo "all healthy"
  ```

  Expected: `all healthy` (tailscale and other check-less containers excepted, knowingly).

## Procedure

1. **Load environment and define the backup set**

   ```bash
   set -a; source /opt/dahouselab/.env; set +a
   BACKUP_DATE=$(date +%F)
   BACKUP_SET="${BACKUP_ROOT}/dahouselab/daily/${BACKUP_DATE}"
   LATEST_LINK="${BACKUP_ROOT}/dahouselab/latest"
   sudo mkdir -p "${BACKUP_SET}"
   ```

   Expected: `${BACKUP_SET}` exists and is empty (re-running on the same day resumes into it).

2. **Quiesce where required.** Only Nextcloud needs quiescing: its files and its database must
   agree, so enable maintenance mode for the duration of its dump + rsync. Everything else is
   safe to hot-dump: `pg_dump` is transaction-consistent, and `sqlite3 .backup` uses the online
   backup API.

   ```bash
   docker exec -u www-data nextcloud php occ maintenance:mode --on
   ```

   Expected: `Maintenance mode enabled`. Immich and paperless-ngx stay up (their originals are
   append-mostly; a consistent DB dump is the recovery anchor).

3. **Dump the Postgres databases** (custom format, into each service's data tree so the rsync
   step carries the dumps into the backup set):

   ```bash
   for svc in nextcloud immich paperless-ngx; do
     sudo mkdir -p "${DATA_ROOT}/${svc}/db-dumps"
     docker exec "${svc}-postgres" pg_dump -U "${POSTGRES_USER:-postgres}" -Fc -d "${svc//-/_}" \
       | sudo tee "${DATA_ROOT}/${svc}/db-dumps/${svc}-${BACKUP_DATE}.dump" > /dev/null
   done
   ```

   Adjust container names, users, and database names to each service's `compose.yaml`/`.env`.
   Expected: three non-empty `.dump` files (`ls -lh "${DATA_ROOT}"/*/db-dumps/`).

4. **Dump the SQLite databases** (online backup API — never `cp` a live SQLite file):

   ```bash
   sudo mkdir -p "${DATA_ROOT}/vaultwarden/db-dumps"
   sudo sqlite3 "${DATA_ROOT}/vaultwarden/db.sqlite3" \
     ".backup '${DATA_ROOT}/vaultwarden/db-dumps/vaultwarden-${BACKUP_DATE}.sqlite3'"
   ```

   Expected: the dump exists and `sqlite3 <dump> "PRAGMA integrity_check;"` prints `ok`.

   > **uptime-kuma (v2.x) is NOT SQLite** — it runs an embedded MariaDB
   > (discovered 2026-07-17; see `services/uptime-kuma/docs/README.md`). There is no safe
   > hot-copy: stop the container immediately before the rsync in step 5 and start it right
   > after (monitors pause for the window — accepted tradeoff). The script does this
   > automatically with a restart guarantee even on failure.

   ```bash
   docker stop uptime-kuma    # right before step 5; docker start uptime-kuma right after
   ```

5. **Rsync config and data into the dated set**, hardlinked against the previous set so
   unchanged files cost no space:

   ```bash
   sudo rsync -aHAX --delete --link-dest="${LATEST_LINK}/config" \
     "${CONFIG_ROOT}/" "${BACKUP_SET}/config/"
   sudo rsync -aHAX --delete --link-dest="${LATEST_LINK}/data" \
     "${DATA_ROOT}/" "${BACKUP_SET}/data/"
   ```

   Expected: exit code 0 for both. `--delete` is safe here — it only applies **inside the new
   dated set**, never toward production. On the very first run `latest` does not exist; rsync
   warns about the missing link-dest and copies everything — that is expected.

6. **End the quiesce window** (do this immediately; do not leave Nextcloud in maintenance mode
   while manifests are computed):

   ```bash
   docker exec -u www-data nextcloud php occ maintenance:mode --off
   ```

   Expected: `Maintenance mode disabled`; Nextcloud web UI responds again.

7. **Write the manifest** — date, sizes, file count, and checksums of every database dump:

   ```bash
   {
     echo "backup_date=${BACKUP_DATE}"
     echo "host=$(hostname)"
     echo "created=$(date -Is)"
     sudo du -sb "${BACKUP_SET}/config" "${BACKUP_SET}/data"
     echo "file_count=$(sudo find "${BACKUP_SET}" -type f | wc -l)"
   } | sudo tee "${BACKUP_SET}/MANIFEST.txt"
   sudo find "${BACKUP_SET}/data" -path '*/db-dumps/*' -name "*${BACKUP_DATE}*" -type f \
     -exec sha256sum {} + | sudo tee "${BACKUP_SET}/SHA256SUMS"
   ```

   Expected: `MANIFEST.txt` with sizes, `SHA256SUMS` with five dump checksums.

8. **Verify the manifest** and promote the set to `latest`:

   ```bash
   sudo sha256sum -c "${BACKUP_SET}/SHA256SUMS"
   sudo ln -sfn "${BACKUP_SET}" "${LATEST_LINK}"
   ```

   Expected: every line `OK`; `readlink "${LATEST_LINK}"` prints today's set.

9. **Retention pruning** per the backup policy (keep 7 daily sets; weekly/monthly promotion is
   a future improvement):

   > **Warning:** this step deletes old backup sets — irreversible. Confirm the list before
   > deleting.

   ```bash
   ls -1d "${BACKUP_ROOT}"/dahouselab/daily/*/ | head -n -7
   ls -1d "${BACKUP_ROOT}"/dahouselab/daily/*/ | head -n -7 | sudo xargs -r rm -rf --
   ```

   Expected: first command lists exactly the sets to delete; after the second, 7 sets remain.

## Verification

- [ ] `sudo sha256sum -c "${LATEST_LINK}/SHA256SUMS"` — all `OK`
- [ ] `sudo diff <(ls "${CONFIG_ROOT}") <(ls "${LATEST_LINK}/config")` — no missing services
- [ ] Nextcloud out of maintenance mode: `docker exec -u www-data nextcloud php occ maintenance:mode` reports disabled
- [ ] All containers still healthy: `docker ps --format '{{.Names}}\t{{.Status}}'`
- [ ] Within the month, run [validate-backup](validate-backup.md) against this set

## Rollback

The procedure is read-only toward production except Nextcloud maintenance mode (step 2/6 —
re-run step 6 if interrupted) and retention pruning (step 9 — irreversible; everything before
it can simply be abandoned by deleting the incomplete `${BACKUP_SET}` directory, leaving
`latest` pointing at the previous good set).

## Troubleshooting

| Symptom                                   | Likely cause                          | Action                                             |
| ----------------------------------------- | ------------------------------------- | -------------------------------------------------- |
| `findmnt` shows nothing for /mnt/backups  | Disk not mounted / fstab entry lost   | `sudo mount /mnt/backups`; check `blkid` vs fstab  |
| `pg_dump` auth failure                    | Wrong user/db for that stack          | Read the service's `compose.yaml` and `.env`       |
| `sqlite3 .backup` says database is locked | Long-running write transaction        | Retry; if persistent, stop the stack and re-dump   |
| rsync exit 23/24 (partial transfer)       | Files changed/vanished mid-copy       | Re-run step 5 — rsync is idempotent                |
| Backup disk >80% full after pruning       | Data growth outpacing disk            | Review retention; budget in `docs/backup/`         |
| Nextcloud stuck in maintenance mode       | Step 6 skipped after failure          | Run step 6 manually                                |

## Automation opportunities

**Realized (2026-07-17):** `scripts/backup/run-backup.sh` implements this runbook — mount guard,
dumps, kuma stop-copy with restart guarantee, rsync rotation, manifest + checksum verify,
pruning, non-zero exit on any failure. Remaining: cron/systemd-timer scheduling with an Uptime
Kuma push monitor on the exit status, and a per-service dump map driven by the
`dahouselab.backup` label instead of the current explicit list.

## Future improvements

- Weekly/monthly retention tiers instead of 7 flat dailies
- Off-site copy 3 (encrypted, e.g. restic/rclone) per the roadmap
- Prune old `db-dumps/` inside `DATA_ROOT` (they accumulate on the data disk too)
- Per-service backup scoping (used by [update-containers](update-containers.md))
