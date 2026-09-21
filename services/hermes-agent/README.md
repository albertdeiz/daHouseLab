# hermes-agent

[Hermes Agent](https://hermes-agent.nousresearch.com/docs/) (Nous Research) — an autonomous AI
agent with persistent memory at `https://hermes.dahub.casa`. It keeps a three-layer memory (skills,
conversation, user model) that improves at recurring tasks, browses the web, and is reachable
through messaging connectors.

It does **not** run a model: inference happens at [DeepSeek](https://api.deepseek.com), which is
what makes it viable on a Raspberry Pi 4 — and what makes it the platform's first service that
cannot function without a third party ([ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)).

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `nousresearch/hermes-agent:v2026.9.21`         |
| URL           | `https://hermes.${DOMAIN}` (dashboard, via Caddy) |
| Ports         | none published — dashboard 9119 and API 8642 stay inside the container |
| Networks      | **`hermes_ingress`** only ([ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)) — deliberately **not** on `proxy` |
| Config path   | — (single app dir; see Data)                   |
| Data path     | `${DATA_ROOT}/hermes-agent` (config, credentials, sessions, skills, memories — single mount) |
| Resource cap  | 4 GB RAM / 2 CPU — hard limit                  |
| Backup        | yes — memories and skills exist only here, not in Git |
| Category      | productivity                                   |

## Deviations from the standards

- **Architectural — own network instead of `proxy`
  ([ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)):** every container on
  `proxy` can reach every other one. That is harmless for an inert service and is a live path to
  `vaultwarden:80` for an agent that executes tools. Hermes joins `hermes_ingress`, shared only with
  Caddy. This is **stricter** than the rule, not looser: ingress still passes through Caddy alone
  ([ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md) is untouched) and no port is
  published.
- **Non-architectural — single mount:** config, credentials and memories all live under `/opt/data`
  (upstream layout), collapsing the two-mount rule into one — documented in `compose.yaml`, as with
  vaultwarden.
- **Non-architectural — resource limits:** the only service besides Immich's ML container with a
  hard `deploy.resources.limits`. Browser automation makes it necessary.

> **The Docker socket is never mounted into this container.** See
> [ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md), condition 3. If a feature
> appears to need it, that needs a new ADR, not a quick edit.

## Dependencies

- Caddy, **attached to `hermes_ingress`** as well as `proxy` — changing Caddy's networks requires
  recreating the container, not just a config reload
- The `hermes_ingress` network, created at deploy
  ([infrastructure/networks](../../infrastructure/networks/README.md))
- A DeepSeek API key with available credit — without it the agent cannot answer at all
- Outbound internet access from the container
- Uptime Kuma deployed, so this service is monitored from day one

## Deployment

Follow the runbook: [deploy-hermes-agent](../../docs/runbooks/deploy-hermes-agent.md).

## Configuration

- Environment: globals via the `.env` symlink
  ([ADR-0012](../../docs/decisions/0012-layered-environment-files.md)); secrets in
  [`.env.service.example`](.env.service.example) — copy to `.env.service`, `chmod 600`.
- **Most configuration is interactive.** `hermes setup` (run inside the container) selects the
  provider, stores the key, picks the model and enables connectors, writing to
  `${DATA_ROOT}/hermes-agent`. Like NetAlertX and Pi-hole, that state is **not** in Git and is
  therefore backup-dependent.
- Provider: DeepSeek, `https://api.deepseek.com`, model `deepseek-v4-pro`.

Details: [`docs/`](docs/README.md).

## Data

`${DATA_ROOT}/hermes-agent` holds the agent's configuration, stored credentials, session history,
self-authored skills and its memory. Growth is driven by conversation volume — modest, but the
content is **sensitive**: it accumulates whatever you have discussed with the agent.

## Backup & restore

- Rides the file backup ([execute-backup](../../docs/runbooks/execute-backup.md)). Any SQLite inside
  the data directory must be dumped or stop-copied, never copied live.
- Restore: [restore-from-backup](../../docs/runbooks/restore-from-backup.md). After restoring,
  re-verify the provider key still works — a rotated key looks exactly like a broken agent.

## Operations

- Health: `docker compose ps` → `healthy`; `curl -sk https://hermes.${DOMAIN}/` → 200
- Logs: `docker compose logs -f hermes-agent`
- Resource watch: `docker stats --no-stream hermes-agent` — it should sit well under the 4 GB cap
- Known failure modes:
  - Agent answers nothing, container healthy → provider problem: expired key, no credit, or DeepSeek
    down. Check `docker compose logs`; the dashboard being up says nothing about inference
  - Container OOM-killed / restarting → browser automation under the 4 GB cap. First lever is
    disabling browser tools, per [ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)
  - Platform-wide slowness after deploy → check `free -h` against the ≥1.5 GiB health floor
  - 502 via `hermes.dahub.casa` → Caddy is not on `hermes_ingress`, or was reloaded instead of
    **recreated** after the network change
  - Unexpected agent actions → treat as possible prompt injection from a browsed page or an inbound
    message. The network isolation bounds the blast radius inside the platform; it does not bound
    what the agent does with its own tools

## References

- Upstream documentation: <https://hermes-agent.nousresearch.com/docs/>
- Provider setup: <https://api-docs.deepseek.com/quick_start/agent_integrations/hermes/>
- Related: [ADR-0015](../../docs/decisions/0015-hermes-agent-self-hosted-ai.md),
  [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md),
  [ADR-0005](../../docs/decisions/0005-raspberry-pi-platform.md)
