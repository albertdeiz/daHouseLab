# homepage — Documentation

Deep documentation for the dashboard. Front page: [`../README.md`](../README.md).

The dashboard's content (tiles, widgets, bookmarks) is **repo-authored config** in
[`infrastructure/configs/homepage/*.yaml`](../../../infrastructure/configs/homepage/), mounted
read-only ([ADR-0008](../../../docs/decisions/0008-configuration-data-separation.md)). Document
notable widget integrations and their API-token handling here as they are added
([documentation conventions](../../../docs/standards/documentation-conventions.md)).

## Current configuration

- `settings.yaml` — dark + minimalist theme (`theme: dark`, `color: slate`, `headerStyle: clean`),
  four groups (Monitoreo, Productividad, Seguridad, Infraestructura) laid out as equal-height rows.
- `services.yaml` — one static tile per deployed service, grouped by `dahouselab.category`. Static
  by design: no Docker socket (see runbook), Uptime Kuma owns live status.
- `widgets.yaml` — header greeting (**static text** — Homepage has no time-of-day logic), a
  `datetime` clock (`es` locale), a `resources` widget (host cpu/memory/uptime + root-fs disk, no
  extra mounts), and a DuckDuckGo `search` bar.
- `bookmarks.yaml` — personal quick links (GitHub, Cloudflare, repo docs); edit freely.

### Adding live service widgets

Service widgets that pull live data (e.g. Nextcloud, Uptime Kuma) need per-service API tokens.
Put the token in `services/homepage/.env.service` (never in the Git-tracked YAML), reference it as
`{{HOMEPAGE_VAR_<NAME>}}` in `services.yaml`, and expose it via `HOMEPAGE_VAR_<NAME>` in the compose
`environment` block — the same pattern as `HOMEPAGE_VAR_DOMAIN`. Uptime Kuma's widget needs only a
public status-page slug (no key).
