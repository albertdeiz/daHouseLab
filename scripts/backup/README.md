# Backup Scripts

Scheduled and on-demand backups of `${CONFIG_ROOT}` and `${DATA_ROOT}` to `${BACKUP_ROOT}`.

Implements [execute-backup](../../docs/runbooks/execute-backup.md); strategy and retention are
defined in [`docs/backup/`](../../docs/backup/README.md).

Rules specific to backup scripts:

- Databases are dumped with native tools (`pg_dump`, etc.) — never file-copied live.
- Every run ends with verification (manifest + size/count sanity checks) and a clear
  success/failure signal that Uptime Kuma can observe.
- Destination is external storage only; scripts refuse to run if `${BACKUP_ROOT}` is not mounted.
