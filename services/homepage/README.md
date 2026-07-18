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
| Config path   | `infrastructure/configs/homepage/*.yaml` (in Git, mounted `:ro`) |
| Data path     | none — this service is stateless; config is Git-tracked |
| Backup        | no — dashboards live in Git (ADR-0008); nothing on host |
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
- Dashboard content lives in [`infrastructure/configs/homepage/*.yaml`](../../infrastructure/configs/homepage/)
  (`settings.yaml`, `services.yaml`, `widgets.yaml`, `bookmarks.yaml`, plus empty `docker.yaml`/
  `kubernetes.yaml` to keep the read-only mount from being written to) — **repo-authored config**
  per [ADR-0008](../../docs/decisions/0008-configuration-data-separation.md), mounted `:ro` exactly
  like the Caddyfile. Edit in Git, commit, `git pull` on the host; Homepage hot-reloads.
  `LOG_TARGETS: stdout` keeps Homepage from writing a log file into the read-only mount (`docker
  compose logs` instead). Hrefs use `{{HOMEPAGE_VAR_DOMAIN}}`, substituted from `HOMEPAGE_VAR_DOMAIN`.
  The Docker socket is **not** mounted (security decision recorded in the runbook); service tiles
  are declared manually.

Details: [`docs/`](docs/README.md).

## Data

None. The dashboards are repo-authored config in `infrastructure/configs/homepage/`; nothing is
persisted on the host. There is no `${CONFIG_ROOT}/homepage` mount.

## Backup & restore

- Nothing to back up: the config is in Git ([ADR-0008](../../docs/decisions/0008-configuration-data-separation.md)) —
  its loss "means nothing, it's in Git."
- Restore: `git pull` on the host and `docker compose up -d` — no database, no migrations, no state.

## Operations

- Health: `docker compose ps` shows `healthy`; `https://home.${DOMAIN}` renders the dashboard.
- Logs: `docker compose logs -f homepage`
- Known failure modes: `Host validation failed` → `HOMEPAGE_ALLOWED_HOSTS` does not match the
  hostname used in the browser.

## References

- Upstream documentation: <https://gethomepage.dev/>
- Related: [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md) (ingress),
  [service structure standard](../../docs/standards/service-structure.md)
