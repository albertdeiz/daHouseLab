# Roadmap

Planned evolution of the platform. The architectural long-term view lives in
[`../architecture/future-plans.md`](../architecture/future-plans.md); this directory tracks the
concrete, ordered work.

## Horizon

| Phase | Theme                        | Highlights                                                       |
| ----- | ---------------------------- | ----------------------------------------------------------------- |
| Now   | Foundation                   | Bootstrap, Docker platform, Caddy, Tailscale, Homepage, Uptime Kuma |
| Next  | Core services                | Nextcloud, Immich, Vaultwarden, Paperless-ngx + their backups     |
| Later | Hardening & automation       | Off-site backups, automated restore testing, centralized logging  |
| Future | Platform evolution          | Mini PC migration, multi-disk storage, CI for infrastructure      |

## Rules

- Roadmap items are outcomes, not tasks ("photos are backed up off-site", not "install rclone").
- Anything that changes architecture graduates into an [ADR](../decisions/) before implementation.
- Completed items move to a dated "Done" section — the roadmap is also a history.
- Review cadence: quarterly, or after any significant incident.
