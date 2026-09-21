# Docker Networks

Definitions and creation scripts for platform-owned Docker networks.

## Network model

| Network              | Type              | Purpose                                            |
| -------------------- | ----------------- | -------------------------------------------------- |
| `proxy`              | External, platform-owned | The only path between Caddy and applications |
| `hermes_ingress`     | External, platform-owned | Isolation network for the AI agent ([ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)) |
| `<service>_internal` | Stack-owned       | Private wiring inside one service's stack (defined in that service's compose file, not here) |

Platform networks are created once, at bootstrap or at the owning service's deploy, before the
services that reference them:

```bash
docker network create proxy
docker network create hermes_ingress
```

## Why a second ingress network exists

On `proxy`, **every container can reach every other one**. That is unremarkable when services are
inert — a photo gallery has no interest in the password manager. It stops being unremarkable for an
*agent*: Hermes executes tools, browses the web and accepts messages, so on `proxy` a manipulated
agent would have a direct route to `vaultwarden:80`.

`hermes_ingress` is shared **only** with Caddy. The agent is reachable through the proxy and can
still egress to the internet (it needs its LLM provider), but has no route to any other service.
This is **stricter** than the standard model, not a loophole: ingress still passes through Caddy
alone and no port is published, so [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md)
stands untouched.

Caddy is consequently attached to **both** networks. That has one operational edge: network
membership is a container property, so adding or removing a network from Caddy requires
`docker compose up -d --force-recreate`, not `caddy reload` — a brief ingress outage.

The pattern generalises: any future service that should not see its neighbours gets its own
`<service>_ingress` network shared only with Caddy. The judgement of *which* services need it is
made per service, in its ADR.

## Rules

- Platform networks are created by bootstrap scripts ([`/scripts/bootstrap`](../../scripts/bootstrap/)),
  referenced by services as `external: true` — a service must never create a platform network as a
  side effect.
- Databases never attach to `proxy` ([compose standard](../../docs/standards/docker-compose-conventions.md)).
- The authoritative port/exposure table lives in [`docs/network/`](../../docs/network/README.md).
