# ADR-0015: Hermes Agent — a Self-Hosted AI Agent on an External LLM API

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-09-21                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0009](0009-caddy-reverse-proxy.md), [ADR-0005](0005-raspberry-pi-platform.md), [ADR-0003](0003-docker-first.md), [ADR-0012](0012-layered-environment-files.md), [deploy-hermes-agent](../runbooks/deploy-hermes-agent.md) |

## Context

The platform hosts no AI services of any kind. The [roadmap](../roadmap/README.md),
[future-plans](../architecture/future-plans.md) and [vision](../architecture/vision.md) contain no
LLM item; [`docs/ai-prompts/`](../ai-prompts/README.md) is about *using* an assistant to edit this
repository, not about hosting one. This ADR opens a new direction rather than continuing a planned
one.

[Hermes Agent](https://hermes-agent.nousresearch.com/docs/) (Nous Research, open source) is an
autonomous agent with persistent memory: a three-layer memory system, autonomous skill creation,
connectors to messaging platforms, and the ability to call MCP servers as tools. Two facts decide
whether it can live here at all:

- **It does not run a model.** Hermes calls a hosted LLM endpoint — Nous Portal, OpenRouter,
  OpenAI, DeepSeek, or any OpenAI-compatible URL. The container is an orchestrator, not an
  inference server.
- **The image is multi-arch.** `nousresearch/hermes-agent` publishes `arm64` and `amd64`, which is
  the hard gate every service must pass ([ADR-0005](0005-raspberry-pi-platform.md)).

Together these make it viable on a Raspberry Pi 4 — a host on which local inference of any useful
size is simply not possible. The cost is that the intelligence lives outside the house.

The platform's existing threat model assumes services are **inert**: they serve requests and do
nothing on their own. Every container on the `proxy` network can reach every other one, which is
harmless for a photo gallery and is not harmless for an agent that executes tools, browses the web,
and accepts input from messaging channels — on the same host as
[Vaultwarden](../../services/vaultwarden/README.md).

## Problem

Do we admit a service that (a) depends on a third-party API to function at all and (b) executes
tools autonomously — and if so, under what containment?

## Alternatives considered

### Option A — Hermes on a hosted LLM API, network-isolated (chosen)

- Run Hermes as a normal container, pointed at a hosted OpenAI-compatible endpoint, on a
  dedicated Docker network shared only with Caddy.
- Pros: works on the existing hardware today; multi-arch; no new ingress; the isolation is free and
  closes the agent's path to the other services before it is opened.
- Cons: the platform gains its first hard dependency on a vendor; prompts and any document content
  the agent handles leave the house.
- Why chosen: it is the only option that delivers the capability on this hardware, and the one cost
  that can be engineered away (lateral reach inside the platform) is engineered away.

### Option B — Hermes with a local model (Ollama / llama.cpp)

- Self-host the model so nothing leaves the network.
- Pros: fully aligned with [vision.md](../architecture/vision.md) — no vendor, no data egress.
- Cons: a Pi 4 has no GPU, 8 GB of shared RAM and an ARM Cortex-A72. Models small enough to run are
  too weak to drive an agent reliably; anything capable is far beyond the hardware. It would also
  collide with the RAM budget Immich already reserves.
- Why not chosen: not a tradeoff but an impossibility on the current host. **This is the option to
  revisit at the Mini PC migration**, and it is why this ADR is written to be superseded rather
  than to be permanent.

### Option C — Do nothing

- No agent.
- Pros: no vendor dependency, no new attack surface, no RAM pressure, no change.
- Cons: forgoes the capability entirely.
- Why not chosen: the operator wants the capability and accepts the stated costs.

## Decision

We will run **Hermes Agent as a containerized service**, with these binding conditions:

1. **A hosted, OpenAI-compatible provider.** The *dependency* is the architectural decision; the
   *provider* is a parameter. Currently **OpenAI**, model `gpt-5.4` — the key in `.env.service`,
   the model in the agent's own `config.yaml` (upstream has no model environment variable). Hermes
   supports 100+ providers and can be reconfigured with `hermes model` without redeploying, so
   changing provider updates this line and the service docs — it does not need a new ADR. The API
   key is a secret in `services/hermes-agent/.env.service`
   ([ADR-0012](0012-layered-environment-files.md)).
2. **Network isolation — the load-bearing condition.** Hermes does **not** join `proxy`. It joins a
   dedicated `hermes_ingress` network to which Caddy is also attached. Caddy reaches Hermes;
   Hermes reaches the internet by NAT; Hermes **cannot reach Vaultwarden or any other service**.
   This is a deliberate, documented departure from "every application joins `proxy`" — it is
   stricter than the rule, not looser, and does not weaken [ADR-0009](0009-caddy-reverse-proxy.md):
   all web ingress still passes through Caddy alone, and no port is published.
3. **The Docker socket is never mounted into this container.** Not for convenience, not for a
   feature, not temporarily. Mounting it would hand host-level control to a process that decides
   its own actions. Any future need that seems to require it requires a new ADR instead.
4. **A hard resource cap.** `memory: 4g`, `cpus: "2.0"`, so the agent cannot starve the platform.
   Only Immich's ML container carries a comparable cap today.
5. **Full feature scope**, as chosen by the operator: browser automation (Playwright/Chromium) and
   messaging connectors enabled. This is the most expensive and widest-surface configuration, and
   it is what the Cons below describe.
6. Least privilege otherwise: pinned image tag, `no-new-privileges:true`, no added capabilities,
   a single data mount under `${DATA_ROOT}`.

## Pros

- The platform gains an agent with persistent memory that improves at recurring tasks.
- It costs no inference hardware: an orchestrator at idle is a few hundred MB.
- The isolation model introduced here (`<service>_ingress`, shared only with Caddy) is reusable for
  any future service that should not see its neighbours.
- The capability arrives without any new ingress: no published port, no firewall rule, TLS from the
  existing Caddy setup.

## Cons

- **The platform is no longer self-sufficient.** Without the provider, Hermes does nothing. Prompts —
  and whatever content the agent is asked to reason over — leave the house. This directly
  contradicts [vision.md](../architecture/vision.md)'s "minimize vendor lock-in" and "self-host
  critical services". It is accepted because the alternative is not having the capability at all on
  this hardware, and it is bounded by keeping Hermes non-critical: nothing else depends on it.
- **An autonomous agent is, by construction, code that decides what to do.** Tool execution, web
  access and messaging inputs mean the failure modes are not the usual ones: prompt injection from
  a fetched page or an inbound message is a real path to unintended action. The network isolation
  limits *where* that can go inside the platform; it does not limit what the agent can do with its
  own tools and its own data.
- **RAM.** Full scope asks 2–4 GB on an 8 GB host where Immich already reserves 2 GB and the health
  floor is ≥1.5 GiB available. Chromium is the consumer. This tightens the platform materially and
  brings the ADR-0005 migration trigger ("sustained RAM/CPU saturation") measurably closer.
- Configuration is interactive (`hermes setup`) and lands in `${DATA_ROOT}`, not in Git — the same
  shape as NetAlertX and Pi-hole, and the same consequence: it is backup-dependent state.

## Consequences

- **A second platform network exists.** `hermes_ingress` is created at deploy and documented in
  [`infrastructure/networks/`](../../infrastructure/networks/README.md). Caddy is now attached to
  two networks, so a Caddyfile reload is no longer sufficient for network changes — Caddy must be
  **recreated**, which is a brief ingress outage.
- **The "Resource budget" concern in [`docs/services/README.md`](../services/README.md) stops being
  a promise.** This ADR introduces the first entry beyond Immich and the table is created with it;
  any further service must state its budget.
- Adding a second cloud dependency (a different provider, a second agent) does **not** inherit this
  decision — the vendor-dependency cost was weighed once, for one capability.
- Disaster recovery is unaffected: Hermes is deliberately non-critical. Nothing else may be built
  to depend on it without revisiting this ADR.

## Operational impact

- Deployment and lifecycle: [deploy-hermes-agent](../runbooks/deploy-hermes-agent.md).
- The deploy gains a pre-flight memory gate (`free -h` ≥ 4 GB) like Immich's, and a **post-deploy
  isolation check** — proving from inside the container that Vaultwarden is unreachable and the
  provider endpoint is. That check is part of the contract, not a nicety.
- API usage costs money. There is no spend cap in the platform; the provider's dashboard is the
  only control, and a runaway agent is a billing incident as well as a technical one.
- Updates follow [update-containers](../runbooks/update-containers.md). Upstream ships dated tags
  (`vYYYY.M.D`) at a high cadence; pin and bump deliberately.

## Security considerations

- **Lateral movement is the risk that was actually engineered against.** On `proxy`, a compromised
  or manipulated agent could reach `vaultwarden:80` directly. On `hermes_ingress` it cannot resolve
  or route to any other service. This is verified at deploy, not assumed.
- **Internet egress remains, by necessity.** The agent must reach its provider, so it can also
  reach anything else outbound. Egress filtering is not implemented and would be the next
  meaningful hardening step.
- **Prompt injection is a live threat** given browser tools and messaging inputs. Mitigations are
  the isolation above, the resource cap, and the absence of the Docker socket — not the agent's own
  judgement.
- **Secrets:** the provider key and any connector tokens live only in
  `services/hermes-agent/.env.service` (`chmod 600`), never in `compose.yaml`, never in Git.
- **No new ingress:** no published ports; the dashboard is reachable only through Caddy over the
  tailnet, and router port-forwarding stays `none` ([ADR-0010](0010-tailscale-remote-access.md)).
- The agent's memory under `${DATA_ROOT}/hermes-agent` accumulates conversation content and should
  be treated as sensitive, like Pi-hole's query log.

## Future review

- **At the Mini PC migration**, re-evaluate Option B: hardware capable of useful local inference
  removes the vendor dependency entirely and would supersede this ADR.
- **If RAM pressure becomes sustained**, the first lever is disabling browser automation (the bulk
  of the footprint), before considering removal.
- **If the agent is ever wanted for something the platform depends on**, this ADR must be revisited
  — its acceptability rests on Hermes being non-critical.
- **If egress filtering becomes available** on the host, revisit whether the agent should be able to
  reach arbitrary destinations.
