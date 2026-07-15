# Backup Documentation

Backup strategy, retention policy, and restore expectations. A backup that has never been
restored is a hypothesis, not a backup.

## Strategy (summary)

Target: a pragmatic 3-2-1 posture, reached incrementally.

| Copy | Location                         | Mechanism                                  |
| ---- | -------------------------------- | ------------------------------------------ |
| 1    | Live data on `DATA_ROOT` (SSD)   | The running system                         |
| 2    | `BACKUP_ROOT` (external disk)    | Scheduled scripts in [`/scripts/backup`](../../scripts/backup/) |
| 3    | Off-site (future)                | Encrypted remote target — see [roadmap](../roadmap/README.md) |

The repository itself is backed up by being Git: a clone on any machine plus a remote.

## What gets backed up

| Content                            | Backed up | Rationale                                  |
| ---------------------------------- | --------- | ------------------------------------------ |
| `CONFIG_ROOT` (runtime config)     | Yes       | Small, expensive to recreate               |
| `DATA_ROOT` (application data)     | Yes       | Irreplaceable                              |
| Databases                          | Yes — via dumps, not file copies | Consistency          |
| The repository                     | Via Git remotes | Already version controlled           |
| Container images                   | No        | Reproducible from registries + pinned tags |
| OS / boot media                    | No        | Reproducible via [bootstrap runbook](../runbooks/bootstrap-raspberry-pi.md) |

## Scope

- Per-service backup requirements (what, how often, consistency mechanism)
- Retention policy and disk-space budgeting
- RPO/RTO expectations per service — how much loss and downtime is acceptable
- Restore-test calendar and results log

## Ground rules

- Backups never live in Git and never on the same disk as the data.
- Databases are backed up with their native dump tool inside a stopped-write window or
  transaction-consistent dump — never by copying live database files.
- Every backup run is verified ([validate-backup](../runbooks/validate-backup.md));
  restores are rehearsed on a schedule ([restore-from-backup](../runbooks/restore-from-backup.md)).
