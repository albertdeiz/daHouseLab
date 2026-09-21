# hermes-agent — Documentation

Deep documentation for the AI agent. Front page: [`../README.md`](../README.md).
The decision and its costs: [ADR-0015](../../../docs/decisions/0015-hermes-agent-self-hosted-ai.md).

## Why this service is shaped differently from every other one

Every other service on the platform is **inert**: it answers requests and does nothing on its own.
The security model leans on that — all containers share the `proxy` network and can reach each
other, which is unremarkable when none of them has any initiative.

An agent breaks that assumption. It executes tools, fetches web pages, accepts messages from
outside, and chooses its own next action. So two things are different here, and both are
deliberate:

1. It runs on **`hermes_ingress`**, a network shared only with Caddy, so it cannot reach
   Vaultwarden or anything else. Being on `proxy` would have given a manipulated agent a direct
   route to the password manager.
2. It has a **hard resource cap**, because browser automation can consume whatever is available on
   an 8 GB host.

Neither is a workaround. They are the conditions under which the service was accepted.

## The isolation, concretely

```
        internet (DeepSeek API)
             ↑ NAT egress
       ┌─────────────┐
       │ hermes-agent│  ── only network: hermes_ingress
       └─────────────┘
             ↑
        hermes_ingress
             ↑
       ┌─────────────┐        ┌───────┐
       │    caddy    │ ────── │ proxy │ ── vaultwarden, nextcloud, pihole, …
       └─────────────┘        └───────┘
```

Caddy is the only container on both networks. Hermes can talk to the internet and be reached by
Caddy; it has no route to the rest of the platform. Verify after any network change:

```bash
docker exec hermes-agent curl -s -m3 http://vaultwarden/alive   # must FAIL
docker exec hermes-agent curl -s -m5 https://api.deepseek.com   # must answer
```

**What this does not protect against:** the agent still has unrestricted outbound internet access,
because it needs to reach its provider. Egress filtering is the next meaningful hardening step and
is not implemented.

## Provider

| Setting  | Value                        | Why |
| -------- | ---------------------------- | --- |
| Provider | DeepSeek                     | Operator's choice; officially supported by Hermes |
| Base URL | `https://api.deepseek.com`   | Per DeepSeek's [Hermes guide](https://api-docs.deepseek.com/quick_start/agent_integrations/hermes/) |
| Model    | `deepseek-v4-pro`            | The model that guide specifies |

Hermes is provider-agnostic — anything speaking the OpenAI chat-completions shape works with a base
URL, a key and a model name. Switching providers is a `hermes setup` run plus a new key in
`.env.service`, not a redeploy.

**Cost is unbounded by the platform.** There is no spend cap here; the provider's dashboard is the
only control. An agent stuck in a loop is a billing incident as much as a technical one — worth a
budget alert on the DeepSeek side.

## Enabled features and what each one costs

Full scope was chosen ([ADR-0015](../../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)).
Record changes here with a date.

| Feature | State | Cost / risk |
| ------- | ----- | ----------- |
| Browser automation (Playwright/Chromium) | on | The bulk of the memory footprint. **First lever to pull** under RAM pressure |
| Messaging connectors | on | Each channel is an inbound path into a tool-executing agent — prompt injection surface |
| MCP client (Hermes calling MCP servers) | as configured | Each server added extends what the agent can do; add deliberately |
| Docker socket | **forbidden** | Would grant host control. Prohibited by the ADR, not merely unused |

## Memory and what accumulates

Hermes keeps skill memory, conversational memory and a user model under
`${DATA_ROOT}/hermes-agent`. Two consequences worth stating plainly:

- **It is sensitive.** The memory accumulates what you have discussed, in the same category as
  Pi-hole's query log. It is inside `DATA_ROOT`, so it is backed up and must be handled like the
  rest of that tree on disk disposal.
- **It is not in Git.** The interactive setup and everything learned since live only on disk. A
  restore that loses this directory loses the agent's accumulated usefulness, not just its config.

## Troubleshooting

Incidents and their resolutions, dated, most recent first.

| Date | Symptom | Cause | Resolution |
| ---- | ------- | ----- | ---------- |
|      |         |       |            |
