# Backup Validation Log

Dated results of [validate-backup](../runbooks/validate-backup.md) runs. A backup that has never
been restored is a hypothesis — every entry here converts a hypothesis into evidence.
Cadence: monthly ([operating rhythm](../operations/README.md)). FAIL entries are incidents.

## 2026-07-17

- **Set:** `/mnt/backups/dahouselab/daily/2026-07-17` (created 02:30, fresh)
- **Manifest:** plausible — config 25 KB, data 200.9 MB, 294 files (first set; no previous to delta against)
- **Checksums:** `SHA256SUMS` — all OK
- **Spot-restore + content diff:** `config/homepage`, `data/vaultwarden` → byte-identical
- **Restore test (vaultwarden):** dump promoted to `db.sqlite3` in staging; throwaway container
  (`--network none`) answered `/alive`; sanity queries: 1 user, 3 cipher items
- **Restore test (uptime-kuma):** staged copy of the stop-copied data dir; throwaway container
  reached healthy and attempted its configured monitors — monitor config restored intact
- **Cleanup:** no `bkval-*` leftovers, staging removed, production untouched (all healthy)
- **Deviations from the runbook:** no Postgres services deployed yet (steps 5–6 replaced by the
  vaultwarden + kuma live-restore tests above, which are stronger); run without host sudo —
  staging copies/diffs performed inside containers (content validated; host-side ownership
  metadata not independently re-verified)
- **Result: PASS** ✅

<!-- Newest entries above this line -->
