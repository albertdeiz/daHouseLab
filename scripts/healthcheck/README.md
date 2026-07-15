# Healthcheck Scripts

Platform verification: one command that answers "is everything actually fine?".

Implements [run-health-checks](../../docs/runbooks/run-health-checks.md). Checks include:

- All expected containers running and healthy (Docker healthchecks green)
- Disk usage below watermarks on `${DATA_ROOT}` and `${BACKUP_ROOT}`
- Latest backup exists and is recent (per policy in [`docs/backup/`](../../docs/backup/README.md))
- Every service in the inventory responds on its canonical URL

Output is human-readable and machine-parseable (exit code reflects overall health) so it can run
interactively, from cron, or as an Uptime Kuma push check.
