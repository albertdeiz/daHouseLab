# nextcloud

Self-hosted [Nextcloud](https://nextcloud.com/) (files, calendar, contacts) at
`https://cloud.dahub.casa`. It replaces third-party cloud storage and CalDAV/CardDAV for the
household — the platform's primary productivity surface, and one of its two largest datasets.
Runs as a four-container stack: the Apache app, a dedicated cron container for background jobs,
PostgreSQL 16, and Redis for cache/locking.

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `nextcloud:31.0.6-apache` (app + cron), `postgres:16.9`, `redis:7.4-alpine` |
| URL           | `https://cloud.${DOMAIN}`                      |
| Networks      | `proxy` (app only), `nextcloud_internal` (all) |
| Config path   | `${CONFIG_ROOT}/nextcloud` (app tree + `config.php`) |
| Data path     | `${DATA_ROOT}/nextcloud/data` (user files, UID 33), `${DATA_ROOT}/nextcloud/db` (Postgres cluster) |
| Backup        | yes — **db and files as a pair** (mismatched restore points desync the file cache) |
| Category      | productivity                                   |

## Dependencies

- `proxy` network + Caddy with working TLS ([deploy-caddy](../../docs/runbooks/deploy-caddy.md))
- Uptime Kuma deployed, so this service is monitored from day one
- ≥ 10 GB free on the data disk to start; user files grow into tens of GB

## Deployment

Follow the runbook: [deploy-nextcloud](../../docs/runbooks/deploy-nextcloud.md).

## Configuration

- Environment: globals via the `.env` symlink ([ADR-0012](../../docs/decisions/0012-layered-environment-files.md));
  service layer in [`.env.service.example`](.env.service.example) — copy to `.env.service`
  (mode 600) and fill the generated DB password.
- Proxy-awareness lives in `compose.yaml` (`OVERWRITEPROTOCOL`, `OVERWRITECLIURL`,
  `TRUSTED_PROXIES`, `NEXTCLOUD_TRUSTED_DOMAINS`) — a wrong `trusted_domains` locks out the web
  UI, fixable via `occ`.
- The db and redis containers are on `nextcloud_internal` only — never on `proxy`.
- Runtime administration is via `occ`: `docker compose exec -u www-data nextcloud php occ ...`.

Details: [`docs/`](docs/README.md).

## Data

- `${DATA_ROOT}/nextcloud/data` — user files, owned by UID 33 (`www-data` in the image), grows
  large; the app refuses a data dir it cannot own.
- `${DATA_ROOT}/nextcloud/db` — PostgreSQL 16 cluster.
- `${CONFIG_ROOT}/nextcloud` — the installed app tree and `config.php` (small, precious).

## Backup & restore

- Back up **db and data together** (per [execute-backup](../../docs/runbooks/execute-backup.md)):
  `occ maintenance:mode --on` → `pg_dump` the cluster + rsync the file tree → `--off`. Restoring
  db and files from different points in time desyncs the file cache.
- Restore: [restore-from-backup](../../docs/runbooks/restore-from-backup.md), then
  `occ files:scan --all` to resync disk with the cache.

## Operations

- Health: `docker compose ps` → all four `healthy`;
  `curl -sk https://cloud.${DOMAIN}/status.php` → `"installed":true`
- Logs: `docker compose logs -f nextcloud`
- Known failure modes:
  - "Access through untrusted domain" → `occ config:system:set trusted_domains 1 --value=cloud.<domain>`
  - Endless redirect / mixed content → proxy headers not trusted; check `OVERWRITEPROTOCOL` / `TRUSTED_PROXIES`
  - `nextcloud` unhealthy on first boot → app-tree copy still running on slow I/O; wait out `start_period`
  - Files on disk missing in UI → `occ files:scan --all`

## References

- Upstream documentation: <https://docs.nextcloud.com/server/latest/admin_manual/>
- Related: [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md),
  [ADR-0011](../../docs/decisions/0011-dns-01-tls-certificates.md),
  [ADR-0012](../../docs/decisions/0012-layered-environment-files.md)
