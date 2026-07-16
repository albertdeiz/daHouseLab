# Services

One directory per deployed service. Each is self-contained and uniformly shaped — see the
[service structure standard](../docs/standards/service-structure.md); new services start as a
copy of [`/templates/service`](../templates/service/).

## Planned portfolio

Deployment order and dependencies live in [`docs/runbooks/`](../docs/runbooks/README.md);
the cross-service inventory lives in [`docs/services/`](../docs/services/README.md).

| Service        | Category       | Purpose                          | Status                          |
| -------------- | -------------- | -------------------------------- | ------------------------------- |
| `tailscale`    | infrastructure | Remote access mesh               | ✅ Deployed (host-level, ADR-0003 exception) |
| `caddy`        | infrastructure | Reverse proxy + TLS              | ✅ Deployed                     |
| `homepage`     | monitoring     | Dashboard → `home.dahub.casa`    | ✅ Deployed                     |
| `uptime-kuma`  | monitoring     | Uptime monitoring → `status.dahub.casa` | ✅ Deployed             |
| `vaultwarden`  | security       | Password manager                 | Planned                         |
| `nextcloud`    | productivity   | Files, calendar, contacts        | Planned                         |
| `immich`       | media          | Photo management                 | Planned                         |
| `paperless-ngx`| productivity   | Document management              | Planned                         |

## Rules

- A service is "deployed" only when: directory complete per the standard, deploy runbook written,
  registered in the inventory, and monitored by Uptime Kuma.
- No service data or runtime config in this tree — compose files reference
  `${CONFIG_ROOT}`/`${DATA_ROOT}` exclusively.
- Retired services move to [`/archive`](../archive/), dated, with a retirement note.
