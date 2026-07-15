# Docker Networks

Definitions and creation scripts for platform-owned Docker networks.

## Network model

| Network              | Type              | Purpose                                            |
| -------------------- | ----------------- | -------------------------------------------------- |
| `proxy`              | External, platform-owned | The only path between Caddy and applications |
| `<service>_internal` | Stack-owned       | Private wiring inside one service's stack (defined in that service's compose file, not here) |

The `proxy` network is created once, at platform bootstrap, before any service deploys:

```bash
docker network create proxy
```

## Rules

- Platform networks are created by bootstrap scripts ([`/scripts/bootstrap`](../../scripts/bootstrap/)),
  referenced by services as `external: true` — a service must never create a platform network as a
  side effect.
- Databases never attach to `proxy` ([compose standard](../../docs/standards/docker-compose-conventions.md)).
- The authoritative port/exposure table lives in [`docs/network/`](../../docs/network/README.md).
