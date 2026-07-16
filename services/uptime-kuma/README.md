# uptime-kuma

Uptime monitoring and alerting ([Uptime Kuma](https://github.com/louislam/uptime-kuma)) at
`https://status.dahub.casa`. It is deployed early — before the big services — so every later
deployment is watched from day one: the platform's rule is that a service isn't "deployed" until
Uptime Kuma monitors it ([service structure standard](../../docs/standards/service-structure.md)).

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `louislam/uptime-kuma:2.0.1`                   |
| URL           | `https://status.${DOMAIN}`                     |
| Networks      | `proxy`                                        |
| Config path   | — (single app dir; see Data)                   |
| Data path     | `${DATA_ROOT}/uptime-kuma` (SQLite + config, one mount — documented deviation from the two-mount rule) |
| Backup        | yes — monitor definitions and history live in the SQLite DB |
| Category      | monitoring                                     |

## Dependencies

- `proxy` network exists ([infrastructure/networks](../../infrastructure/networks/README.md))
- Caddy deployed and routing `status.{$DOMAIN}` ([deploy-caddy](../../docs/runbooks/deploy-caddy.md))

## Deployment

Follow the runbook: [deploy-uptime-kuma](../../docs/runbooks/deploy-uptime-kuma.md) — including
the post-deploy step of adding monitors for every already-running service.

## Configuration

- Environment: see [`.env.example`](.env.example) — no secrets.
- Everything else (monitors, notification channels, users) is configured in the web UI and
  persisted in the SQLite database under `${DATA_ROOT}/uptime-kuma`.

Details: [`docs/`](docs/README.md).

## Data

`${DATA_ROOT}/uptime-kuma`: SQLite database (monitor definitions, heartbeat history) plus app
config. Growth is slow and bounded by history retention (configurable in the UI).

## Backup & restore

- SQLite must be backed up with `sqlite3 .backup` or with the container stopped — never a live
  file copy ([execute-backup](../../docs/runbooks/execute-backup.md)).
- Restore: repopulate `${DATA_ROOT}/uptime-kuma` and `docker compose up -d`
  ([restore-from-backup](../../docs/runbooks/restore-from-backup.md)).

## Operations

- Health: `docker compose ps` shows `healthy`; `https://status.${DOMAIN}` renders the dashboard.
- Logs: `docker compose logs -f uptime-kuma`
- Known failure modes: UI unreachable but container healthy → check the Caddy site block /
  `proxy` network attachment.

## References

- Upstream documentation: <https://github.com/louislam/uptime-kuma/wiki>
- Related: [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md) (ingress),
  [docs/operations](../../docs/operations/README.md) (monitoring rhythm)
