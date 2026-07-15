# Services

One directory per deployed service. Each is self-contained and uniformly shaped — see the
[service structure standard](../docs/standards/service-structure.md); new services start as a
copy of [`/templates/service`](../templates/service/).

## Planned portfolio

Deployment order and dependencies live in [`docs/runbooks/`](../docs/runbooks/README.md);
the cross-service inventory lives in [`docs/services/`](../docs/services/README.md).

| Service        | Category       | Purpose                          |
| -------------- | -------------- | -------------------------------- |
| `tailscale`    | infrastructure | Remote access mesh               |
| `caddy`        | infrastructure | Reverse proxy + TLS              |
| `homepage`     | monitoring     | Dashboard                        |
| `uptime-kuma`  | monitoring     | Uptime monitoring + alerts       |
| `vaultwarden`  | security       | Password manager                 |
| `nextcloud`    | productivity   | Files, calendar, contacts        |
| `immich`       | media          | Photo management                 |
| `paperless-ngx`| productivity   | Document management              |

## Rules

- A service is "deployed" only when: directory complete per the standard, deploy runbook written,
  registered in the inventory, and monitored by Uptime Kuma.
- No service data or runtime config in this tree — compose files reference
  `${CONFIG_ROOT}`/`${DATA_ROOT}` exclusively.
- Retired services move to [`/archive`](../archive/), dated, with a retirement note.
