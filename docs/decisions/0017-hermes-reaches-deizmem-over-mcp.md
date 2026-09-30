# ADR-0017: Hermes Reaches deizmem over MCP on a Dedicated Internal Network

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-09-27                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0015](0015-hermes-agent-self-hosted-ai.md), [ADR-0012](0012-layered-environment-files.md), [connect-hermes-to-deizmem](../runbooks/connect-hermes-to-deizmem.md), [infrastructure/networks](../../infrastructure/networks/README.md) |

## Context

deizmem (<https://github.com/albertdeiz/deizmem>) is a personal memory service: it stores files and notes
(policies, prescriptions, receipts, voice notes) and returns them with evidence. It runs **no
LLM**: classification, fact extraction and prose are the agent's job, and it exposes its
operations as an MCP server (streamable HTTP, bearer token per owner). Its stack runs on the Pi
from `/opt/deizmem`, outside this repository, while it is being proven. It follows the same split
this platform uses for itself: the checkout in `/opt` is disposable and re-clonable, its state
lives in `/srv/deizmem` (`DEIZMEM_DATA`), and neither is inside the other. It was moved there from
a home directory on 2026-09-28, when its database and blobs still lived inside the checkout —
which made "delete and re-clone" a destructive operation on medical records.

Hermes ([ADR-0015](0015-hermes-agent-self-hosted-ai.md)) is deliberately isolated: it joins only
`hermes_ingress`, shared with Caddy, precisely so that a manipulated agent cannot reach any other
service. Hermes has a native MCP client (`mcp_servers` in `config.yaml`, with `${VAR}`
interpolation in headers).

deizmem is unrelated to [memvid](0016-memvid-personal-knowledge-base.md) and to Nextcloud: it
knows neither, and neither knows it. They are different capabilities with different inputs.

## Problem

How does Hermes reach deizmem's MCP endpoint without weakening the isolation ADR-0015 exists for?

## Alternatives considered

### Option A — A dedicated internal network shared by Hermes and deizmem's `mcp` only (chosen)

- A platform network `deizmem_mcp`, created `--internal` (no external routing), joined by Hermes
  and by deizmem's `mcp` container alone, which answers there as `deizmem-mcp`.
- Pros: Hermes gains exactly one new reachable endpoint and nothing else; deizmem's database,
  blobs and lanes stay on its own stack network; no port is published; follows the
  `<service>_ingress` pattern of a network per purpose.
- Cons: a third network on Hermes; one more platform network to create before deploying.
- Why chosen: it is the narrowest path that works.

### Option B — Put Hermes on `proxy` or on deizmem's default network

- Pros: no new network.
- Cons: `proxy` reopens the route to Vaultwarden that ADR-0015 closed; deizmem's default network
  exposes Postgres and every lane to the agent.
- Why not chosen: it undoes the load-bearing condition of ADR-0015.

### Option C — Reach deizmem through the host's published port (`127.0.0.1:4319`)

- Pros: no network change at all.
- Cons: from inside a container, the host loopback is not reachable without `host-gateway` tricks
  that open a path to *every* port the host publishes on loopback.
- Why not chosen: broader than Option A while looking smaller.

## Decision

We will create the platform network `deizmem_mcp` as `--internal`, attach Hermes and deizmem's
`mcp` service to it, and configure Hermes with an `mcp_servers.deizmem` entry pointing at
`http://deizmem-mcp:4319/mcp`. The bearer token lives in Hermes's `.env.service` as
`DEIZMEM_MCP_TOKEN` (ADR-0012), referenced from `config.yaml` as `${DEIZMEM_MCP_TOKEN}`, never
written into `config.yaml` itself. The token is minted by the operator (`dm pair` → `dm token`)
and is revocable (`dm revoke`).

## Pros

- Hermes can capture and recall the person's documents with citations, which is the point.
- The isolation of ADR-0015 holds for everything except this one endpoint.
- deizmem's MCP surface is closed: no purge, no reprocess, no pairing, no SQL or shell.

## Cons

- **This is the most sensitive data on the platform, now readable by the agent.** A prompt-injected
  Hermes (browser tools, messaging inputs) can read medical and financial documents through MCP
  and, since internet egress is not filtered (ADR-0015), exfiltrate them. The isolation limits
  *lateral movement*; it does not limit what the agent does with what it is allowed to read.
- **Document text reaches the LLM provider.** Every memory the agent reads is sent to Hermes's
  provider (NVIDIA-hosted model as of 2026-09-27). deizmem runs no model; the agent does.
- The agent can also hide memories and change the category registry. Registry changes require
  `confirm: true`, but that asserts the agent's claim that the person agreed, not a proof of it.

## Consequences

- A third platform network exists; created at deploy by the
  [connect-hermes-to-deizmem](../runbooks/connect-hermes-to-deizmem.md) runbook and documented in
  [`infrastructure/networks/`](../../infrastructure/networks/README.md).
- Hermes must be started after the network exists, or `docker compose up` fails.
- Revoking the token (`dm revoke <session>`) cuts Hermes off from the memory immediately, without
  touching Hermes.
- Egress filtering on Hermes, already "the next meaningful hardening step" in ADR-0015, becomes
  more valuable: it is what would turn a successful injection from a leak into a failed request.
- If deizmem ever moves from `/opt/deizmem` into `services/`, this ADR stands; only paths change.
- **Amended 2026-09-30: a shared inbox.** An agent that cannot send a file's bytes over MCP can
  still capture it: Hermes mounts `/srv/deizmem/inbox` at `/inbox`, drops the file there and calls
  `memory_capture` with `path: "/inbox/<file>"`. deizmem's `mcp` mounts the same directory
  read-only and reads nothing outside it (`DM_CAPTURE_DIRS`, realpath-checked). This is a second
  path into deizmem besides MCP, but a narrow one: it holds only what Hermes itself put there, and
  exposes no blob, no database and no other file of deizmem. A file left in the inbox stays there
  until someone removes it; the memory keeps its own copy.
