# homepage

Platform dashboard ([gethomepage](https://gethomepage.dev/)) — the front door of daHouseLab at
`https://home.dahub.casa`. It exists so every service has one discoverable entry point instead of
a memorized list of subdomains; as the portfolio grows, this page is the platform's table of
contents.

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `ghcr.io/gethomepage/homepage:v1.3.2`          |
| URL           | `https://home.${DOMAIN}`                       |
| Networks      | `proxy`                                        |
| Config path   | `${CONFIG_ROOT}/homepage` (YAML dashboards)    |
| Data path     | none — this service is stateless beyond config |
| Backup        | yes — config only (small, hand-authored YAML)  |
| Category      | monitoring                                     |

## Dependencies

- `proxy` network exists ([infrastructure/networks](../../infrastructure/networks/README.md))
- Caddy deployed and routing `home.{$DOMAIN}` ([deploy-caddy](../../docs/runbooks/deploy-caddy.md))

## Deployment

Follow the runbook: [deploy-homepage](../../docs/runbooks/deploy-homepage.md).

## Configuration

- Environment: globals via the `.env` symlink ([ADR-0012](../../docs/decisions/0012-layered-environment-files.md));
  service layer in [`.env.service.example`](.env.service.example). `HOMEPAGE_ALLOWED_HOSTS` must match the
  public hostname or the UI returns `Host validation failed`.
- Dashboard content lives in `${CONFIG_ROOT}/homepage/*.yaml` (`services.yaml`,
  `widgets.yaml`, `settings.yaml`, `bookmarks.yaml`) — runtime configuration, edited on the host,
  captured by backups. The Docker socket is **not** mounted (security decision recorded in the
  runbook); service tiles are declared manually.

Details: [`docs/`](docs/README.md).

## Data

None. Everything under `${CONFIG_ROOT}/homepage` is configuration; growth is negligible.

## Backup & restore

- `${CONFIG_ROOT}/homepage` rides the standard config backup ([execute-backup](../../docs/runbooks/execute-backup.md)).
- Restore: repopulate that directory and `docker compose up -d` — no database, no migrations.

## Operations

- Health: `docker compose ps` shows `healthy`; `https://home.${DOMAIN}` renders the dashboard.
- Logs: `docker compose logs -f homepage`
- Known failure modes: `Host validation failed` → `HOMEPAGE_ALLOWED_HOSTS` does not match the
  hostname used in the browser.

## References

- Upstream documentation: <https://gethomepage.dev/>
- Related: [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md) (ingress),
  [service structure standard](../../docs/standards/service-structure.md)
