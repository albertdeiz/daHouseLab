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
        internet (OpenAI API)
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
docker exec hermes-agent curl -s -m5 https://api.openai.com/v1/models   # must answer
```

**What this does not protect against:** the agent still has unrestricted outbound internet access,
because it needs to reach its provider. Egress filtering is the next meaningful hardening step and
is not implemented.

## Provider

| Setting  | Value      | Lives in | Why |
| -------- | ---------- | -------- | --- |
| Provider | OpenAI     | `config.yaml` | Operator's choice; a first-class Hermes provider |
| API key  | —          | **`.env.service`** | Secret ([ADR-0012](../../../docs/decisions/0012-layered-environment-files.md)) |
| Base URL | default    | `.env.service` (`OPENAI_BASE_URL`) | Only needed for a non-standard endpoint (e.g. Azure OpenAI) |
| Model    | `gpt-5.4`  | `config.yaml` | General-purpose tier. Tool-call failures usually mean the model is too small, not that the config is wrong |

### There is no environment variable for the model

This trips people up, so it is worth stating flatly. Upstream's rule is **"secrets go in `.env`;
everything else goes in `config.yaml`"** — which happens to match this platform's own layering.
Concretely:

- `LLM_MODEL` **was removed** upstream. Setting it does nothing.
- `HERMES_MODEL` exists but only overrides a **single `hermes -z` / `hermes chat` invocation**
  (for scripted callers). It does **not** set the model for the running gateway, which is how this
  service runs.
- The model lives in `config.yaml` under `${DATA_ROOT}/hermes-agent`, set by `hermes setup` or
  `hermes model`, and switched in-session with `/model`.

The practical consequence: **the model choice is not in Git.** Like the rest of the interactive
setup, it is backup-dependent state — a restore that loses the data directory loses the model
selection too.

`config.yaml` also supports a top-level `fallback_providers` list (provider + model pairs) for
automatic failover when the primary errors. Not configured here; worth considering if a provider
outage ever leaves the agent mute.

Hermes is provider-agnostic — it supports 100+ providers, and anything speaking the OpenAI
chat-completions shape works with a base URL, a key and a model name. **The provider is a
parameter, not architecture**: `hermes model` adds or reconfigures one, `/model` switches between
those already configured, and neither needs a redeploy. Self-hosted backends (Ollama, vLLM,
llama.cpp) are supported too — that is the path out of the vendor dependency at the Mini PC
migration ([ADR-0015](../../../docs/decisions/0015-hermes-agent-self-hosted-ai.md) Option B).

**Cost is unbounded by the platform.** There is no spend cap here; the provider's dashboard is the
only control. An agent stuck in a loop is a billing incident as much as a technical one — worth a
spend limit on the OpenAI side.

## Enabled features and what each one costs

Full scope was chosen ([ADR-0015](../../../docs/decisions/0015-hermes-agent-self-hosted-ai.md)).
Record changes here with a date.

| Feature | State | Cost / risk |
| ------- | ----- | ----------- |
| Dashboard auth (`dashboard.basic_auth`) | required | Upstream refuses to bind a non-loopback address without an auth provider. Not optional: without it nothing listens on 9119 and Caddy 502s |
| Terminal backend | `local` (unsandboxed) | Agent work dispatched via the API runs with full terminal/file access **inside the container**. Upstream suggests `terminal.backend: docker`, which we **cannot** use — it needs the Docker socket, forbidden by ADR-0015 condition 3. The other half of upstream's advice (firewall the port) is already satisfied: no port is published and `hermes_ingress` holds only Caddy |
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
  This now includes the dashboard password hash and the model selection.

## Host requirement: the memory cgroup

The 4 GB cap in `compose.yaml` is **not enforced** unless the kernel has the memory cgroup enabled.
Raspberry Pi OS ships it disabled, and Docker does not fail — it prints
`Your kernel does not support memory limit capabilities ... Limitation discarded` and starts the
container with no limit at all. `docker inspect` then reports `Memory: 0` and `docker stats` shows
`0B / 0B`, which is the tell.

```bash
grep ^memory /proc/cgroups          # 4th column must be 1
cat /proc/cmdline | tr ' ' '\n' | grep cgroup
```

Note that `/boot/firmware/cmdline.txt` can look clean while `/proc/cmdline` contains
`cgroup_disable=memory` — the firmware appends it. Trust `/proc/cmdline`. The fix is to append
`cgroup_enable=memory cgroup_memory=1` to that single line and reboot (done 2026-09-21).

## Troubleshooting

Incidents and their resolutions, dated, most recent first.

| Date | Symptom | Cause | Resolution |
| ---- | ------- | ----- | ---------- |
|      |         |       |            |
