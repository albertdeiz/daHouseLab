# Docker Compose Conventions

## Why

Every service is deployed with Docker Compose ([ADR-0004](../decisions/0004-docker-compose.md)).
When every compose file has the same shape, operating any service requires learning only one —
and scripts and AI assistants can reason about all of them uniformly.

## File conventions

| Rule            | Convention                                                        |
| --------------- | ------------------------------------------------------------------ |
| Filename        | `compose.yaml` (the modern canonical name — not `docker-compose.yml`) |
| Location        | `services/<name>/compose.yaml`, one stack per service directory    |
| Project name    | Set explicitly: `name: <service>` at the top of the file           |
| Overrides       | `compose.override.yaml` is git-ignored — local experiments only    |

## Service definition rules

```yaml
name: vaultwarden

services:
  vaultwarden:
    image: vaultwarden/server:1.32.0        # 1. Always pin a version. Never :latest.
    container_name: vaultwarden             # 2. Container name = service name.
    restart: unless-stopped                 # 3. Always unless-stopped.
    env_file: .env                          # 4. Secrets/config via .env, never inline.
    environment:
      TZ: ${TZ}
    volumes:                                # 5. Bind mounts only — no named/anonymous volumes.
      - ${CONFIG_ROOT}/vaultwarden:/config
      - ${DATA_ROOT}/vaultwarden:/data
    networks:
      - proxy                               # 6. Reachable only through the proxy network.
    security_opt:
      - no-new-privileges:true              # 7. Least privilege by default.
    healthcheck:                            # 8. Every service defines a healthcheck.
      test: ["CMD", "curl", "-fsS", "http://localhost:80/alive"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    labels:                                 # 9. Standard labels (see below).
      dahouselab.service: "vaultwarden"
      dahouselab.category: "security"
      dahouselab.description: "Password manager"
      dahouselab.url: "https://vault.${DOMAIN}"
      dahouselab.backup: "true"

networks:
  proxy:
    external: true                          # 10. The proxy network is platform-owned.
```

The numbered rules above are **mandatory**. Deviations require a comment in the compose file
explaining why, and an ADR if the deviation is architectural.

## Images

- Pin to at least minor version (`:1.32.0` or `:1.32`); record the pin's date when updating.
- Prefer official/first-party images; multi-arch images are required (must run on ARM64 and x86_64
  — hardware independence, [ADR-0005](../decisions/0005-raspberry-pi-platform.md)).
- Updates happen via the [update-containers runbook](../runbooks/update-containers.md), never ad-hoc.

## Networks

| Network              | Purpose                                          | Created by                          |
| -------------------- | ------------------------------------------------ | ----------------------------------- |
| `proxy` (external)   | Caddy ↔ applications; the only ingress path      | `infrastructure/networks/`          |
| `<service>_internal` | Private app ↔ database wiring within one stack   | The service's own compose file      |

- Only Caddy publishes ports 80/443 on the host. Applications must **not** use `ports:` unless a
  protocol cannot traverse the proxy (document why in the compose file + the port table in
  [`docs/network/`](../network/README.md)).
- Databases attach only to their stack's internal network — never to `proxy`.

## Labels

All labels are namespaced `dahouselab.*`:

| Label                      | Required | Values / example                                  |
| -------------------------- | -------- | ------------------------------------------------- |
| `dahouselab.service`       | Yes      | Service name, matches directory name              |
| `dahouselab.category`      | Yes      | `infrastructure` \| `productivity` \| `media` \| `security` \| `monitoring` |
| `dahouselab.description`   | Yes      | One line, for dashboards                          |
| `dahouselab.url`           | If web UI | Canonical URL behind the proxy                   |
| `dahouselab.backup`        | Yes      | `"true"` / `"false"` — drives backup tooling      |

Proxy routing lives in the Caddyfile (`infrastructure/configs/`), not in labels — Caddy does not
consume Docker labels; keeping routing in one reviewed file is deliberate.

## Tradeoffs

- Pinned versions mean updates are manual work — accepted: unattended major upgrades break
  services at the worst time.
- Bind-mounts-only forgoes some volume-driver features — accepted for transparent, portable,
  rsync-able storage ([ADR-0006](../decisions/0006-bind-mount-strategy.md)).
