# Runbook: Validate backup

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 30 minutes                                   |
| Risk level      | Low                                          |
| Automation      | Manual — target home: `scripts/backup/`      |

## Purpose

Prove — monthly, per the [operating rhythm](../operations/README.md) — that the latest backup
set is actually restorable, without touching production. A backup that has never been restored
is a hypothesis, not a backup. On success, a dated entry in the validation log in
[`docs/backup/`](../backup/README.md) records that the set was fresh, complete, and that a
database dump restored cleanly into a throwaway container.

## Scope

Covers: manifest freshness and integrity, spot-restoring sample files to a staging directory,
and a full test-restore of one Postgres dump plus an integrity check of one SQLite dump.
Does not cover: restoring anything into production ([restore-from-backup](restore-from-backup.md))
or the full quarterly restore rehearsal. Validation is read-only against `${BACKUP_ROOT}` and
writes only to a scratch staging directory and a throwaway container.

## Prerequisites

- [ ] A backup set exists: `readlink /mnt/backups/dahouselab/latest`
- [ ] [execute-backup](execute-backup.md) has run within its schedule
- [ ] Docker available and enough free space for staging: `df -h /srv/dahouselab`
- [ ] Global env loadable: `test -f /opt/dahouselab/.env && echo OK`

## Risks

Worst case is small by design: the throwaway container could collide with a production
container name, or staging could fill the data disk. Mitigations: the test container is named
`bkval-postgres` (no production service uses that name), attaches to no compose network, and
publishes no ports; staging lives in a dedicated scratch path deleted at the end. The real risk
this runbook mitigates is silent backup rot — treat any failed check as an incident.

## Safety checks

- [ ] The staging path is outside `${CONFIG_ROOT}`/`${DATA_ROOT}` service trees and outside
  `${BACKUP_ROOT}`:

  ```bash
  STAGING=/srv/dahouselab/staging/backup-validate-$(date +%F)
  echo "${STAGING}"
  ```

  Expected: a path under `/srv/dahouselab/staging/` — never under `/mnt/backups`.

- [ ] No production container is named like the test container:

  ```bash
  docker ps -a --format '{{.Names}}' | grep -x bkval-postgres || echo "name free"
  ```

  Expected: `name free`.

## Procedure

1. **Load environment and locate the latest set**

   ```bash
   set -a; source /opt/dahouselab/.env; set +a
   BACKUP_SET=$(readlink -f "${BACKUP_ROOT}/dahouselab/latest")
   echo "Validating: ${BACKUP_SET}"
   ```

   Expected: an absolute dated path, e.g. `/mnt/backups/dahouselab/daily/2026-07-14`.

2. **Check manifest freshness and plausibility.** The set must be no older than the backup
   schedule allows (RPO), and not suspiciously smaller than the previous set:

   ```bash
   grep -E 'backup_date|created' "${BACKUP_SET}/MANIFEST.txt"
   grep -E '^[0-9]+' "${BACKUP_SET}/MANIFEST.txt"
   PREV=$(ls -1d "${BACKUP_ROOT}"/dahouselab/daily/*/ | tail -n 2 | head -n 1)
   grep -E '^[0-9]+' "${PREV}/MANIFEST.txt"
   ```

   Expected: `backup_date` within schedule; config/data byte counts within ~10% of the previous
   set unless a known change explains it. A sudden large shrink means an incomplete backup —
   stop and investigate.

3. **Verify the recorded checksums** of all database dumps in the set:

   ```bash
   sudo sha256sum -c "${BACKUP_SET}/SHA256SUMS"
   ```

   Expected: every line ends `OK`. Any `FAILED` means on-disk corruption — fail validation.

4. **Spot-restore sample files to staging** and compare byte-for-byte against the backup
   (proves the copy is readable end to end, including permissions and ownership metadata):

   ```bash
   sudo mkdir -p "${STAGING}"
   sudo rsync -aHAX "${BACKUP_SET}/config/caddy/" "${STAGING}/caddy/"
   sudo rsync -aHAX "${BACKUP_SET}/data/vaultwarden/" "${STAGING}/vaultwarden/"
   sudo diff -r "${BACKUP_SET}/config/caddy" "${STAGING}/caddy" && echo "config sample OK"
   sudo diff -r "${BACKUP_SET}/data/vaultwarden" "${STAGING}/vaultwarden" && echo "data sample OK"
   ```

   Expected: both `OK` lines, no diff output. Rotate the sampled services each month.

5. **Test-restore a Postgres dump into a throwaway container.** Rotate the tested service
   monthly (nextcloud → immich → paperless-ngx). Match the production Postgres major version:

   ```bash
   DUMP=$(sudo ls -t "${BACKUP_SET}"/data/nextcloud/db-dumps/*.dump | head -n 1)
   docker run -d --name bkval-postgres --network none \
     -e POSTGRES_PASSWORD=validate-only postgres:16
   until docker exec bkval-postgres pg_isready -U postgres -q; do sleep 2; done
   sudo cat "${DUMP}" | docker exec -i bkval-postgres \
     pg_restore -U postgres --create --exit-on-error -d postgres
   ```

   Expected: `pg_restore` exits 0 with no error output.

6. **Run sanity queries** against the restored database — row counts in tables that must never
   be empty on a real instance:

   ```bash
   docker exec bkval-postgres psql -U postgres -d nextcloud -Atc \
     "SELECT count(*) FROM pg_tables WHERE schemaname='public';"
   docker exec bkval-postgres psql -U postgres -d nextcloud -Atc \
     "SELECT count(*) FROM oc_users;"
   ```

   Expected: table count > 50 for Nextcloud; user count ≥ 1. For immich use `users`; for
   paperless-ngx use `documents_document` — adjust to the service under test.

7. **Integrity-check one SQLite dump** directly from the backup set:

   ```bash
   sudo sqlite3 "file:$(sudo ls -t "${BACKUP_SET}"/data/vaultwarden/db-dumps/*.sqlite3 | head -n 1)?mode=ro" \
     "PRAGMA integrity_check;"
   ```

   Expected: `ok`.

8. **Tear down staging and the throwaway container**

   ```bash
   docker rm -f bkval-postgres
   sudo rm -rf "${STAGING}"
   ```

   Expected: container gone (`docker ps -a | grep bkval` empty), staging removed.

9. **Record the result** as a dated entry in the validation log,
   `docs/backup/validation-log.md`, committed to Git:

   ```bash
   cd /opt/dahouselab
   printf '\n## %s\n- Set: %s\n- Checksums: OK\n- Spot-restore: caddy config, vaultwarden data — OK\n- DB test-restore: nextcloud (postgres:16) — OK, %s users\n- Result: PASS\n' \
     "$(date +%F)" "${BACKUP_SET}" "<count>" >> docs/backup/validation-log.md
   git add docs/backup/validation-log.md && git commit -m "docs(backup): validation log $(date +%F)"
   ```

   Expected: a committed PASS (or FAIL, with findings) entry. FAIL entries are incidents —
   post-mortem in [`docs/operations/`](../operations/README.md).

## Verification

- [ ] Validation log has today's dated entry with an explicit PASS/FAIL
- [ ] `docker ps -a --format '{{.Names}}' | grep bkval` — empty (no leftovers)
- [ ] `sudo ls /srv/dahouselab/staging/` — no leftover `backup-validate-*` directories
- [ ] Production untouched: `docker ps --format '{{.Names}}\t{{.Status}}'` all healthy

## Rollback

N/A in the usual sense — nothing in production changes. "Rollback" is step 8 (cleanup), which
can be run at any point to abandon the validation.

## Troubleshooting

| Symptom                                    | Likely cause                             | Action                                                  |
| ------------------------------------------ | ---------------------------------------- | ------------------------------------------------------- |
| `latest` symlink missing or dangling       | Backup never ran / disk swapped          | Run [execute-backup](execute-backup.md); investigate    |
| Checksum FAILED                            | Bit rot or interrupted backup            | Fail validation; re-run backup; consider disk health (`smartctl`) |
| `pg_restore` version mismatch errors       | Test container major ≠ dump's producer   | Use the same Postgres major as the service's compose file |
| `pg_restore: error: could not execute ...` | Truncated/corrupt dump                   | FAIL — the dump step in execute-backup is broken        |
| Sanity query returns 0 rows                | Dumped the wrong/empty database          | FAIL — check db name/user in the dump loop              |
| Staging diff shows ownership differences   | rsync run without sudo                   | Re-run step 4 with sudo (`-aHAX` needs root to apply)   |

## Automation opportunities

`scripts/backup/validate-backup.sh`: freshness + size-delta + checksum checks and the SQLite
integrity check are fully scriptable today and should run automatically after every backup;
the Postgres test-restore is scriptable with a service-rotation state file. Only step 9's
human judgment (PASS/FAIL narrative) stays manual — the script can pre-fill the log entry.

## Future improvements

- Automatic size-anomaly detection with history, not a single previous-set comparison
- Restore-test all three Postgres services quarterly instead of one per month
- Push validation PASS/FAIL to an Uptime Kuma push monitor so a missed validation alerts
