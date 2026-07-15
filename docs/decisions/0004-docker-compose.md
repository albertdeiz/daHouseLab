# ADR-0004: Docker Compose as Orchestrator

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0002, ADR-0003, ADR-0005, ADR-0007, ADR-0009 |

## Context

[ADR-0003](0003-docker-first.md) puts every application in a container; something must now define
and run those containers declaratively, from files in this repo
([ADR-0002](0002-infrastructure-as-code.md)). The fleet is exactly one node — a Raspberry Pi 4
with 8 GB RAM ([ADR-0005](0005-raspberry-pi-platform.md)) — hosting on the order of ten
small services. There is no high-availability requirement: the accepted failure model is fast,
documented rebuild, not redundancy.

Each service consists of one to a few containers plus bind mounts and a shared `proxy` network
([ADR-0009](0009-caddy-reverse-proxy.md)). The orchestrator's own complexity is pure overhead at
this scale: every layer it adds must be learned, patched, documented and debugged by a single
operator.

## Problem

Which orchestrator turns the per-service definitions in this repo into running containers on a
single node?

## Alternatives considered

### Option A — Kubernetes (k3s)

- Summary: run k3s single-node; define services as Kubernetes manifests or Helm charts.
- Pros:
  - Industry-standard API; enormous ecosystem (Helm, operators, GitOps controllers).
  - Genuine path to multi-node later; highly transferable skills.
  - Declarative reconciliation loop is a better IaC model than imperative `up`.
- Cons:
  - Control-plane overhead (~0.5–1 GB RAM and constant CPU) is a real tax on an 8 GB Pi.
  - Massive concept surface (pods, services, ingress, PVCs, RBAC) for a workload of ~10
    containers; every simple task acquires three layers of YAML.
  - Single-node Kubernetes delivers none of Kubernetes' actual value (scheduling across nodes,
    self-healing via rescheduling) while charging full complexity price.
- Why not chosen: it is the right answer to a fleet-sized question this platform is not asking.
  Complexity must be earned by requirements, and node count is 1.

### Option B — Docker Swarm

- Summary: `docker swarm init` on the single node; deploy stacks with compose-format files.
- Pros:
  - Built into Docker; stack files are near-compose syntax; secrets support.
  - Cheapest possible upgrade path to a few nodes.
- Cons:
  - Effectively in maintenance mode upstream; ecosystem and community have moved on — a bad bet
    for a platform meant to last years.
  - Swarm-mode networking (overlay, ingress mesh) adds indirection with zero benefit on one node.
  - Subtle divergences from plain Compose (no `depends_on` conditions, different env handling)
    mean docs and examples routinely don't apply.
- Why not chosen: all of Swarm's value is multi-node; its cost (a stagnating layer) is paid
  immediately.

### Option C — Podman + systemd (Quadlet)

- Summary: rootless Podman containers managed as systemd units via Quadlet files.
- Pros:
  - Daemonless and rootless by default — a genuinely better security posture.
  - systemd gives mature dependency ordering, restart policy and journald logging.
- Cons:
  - The self-hosting ecosystem documents Compose, not Quadlet; every service becomes a
    translation exercise, and `podman-compose` compatibility is perpetually partial.
  - Two definition layers (container files + unit files) versus one `compose.yaml`.
  - Rootless networking on Raspberry Pi OS adds friction (ports < 1024, performance of
    slirp/pasta) exactly where the reverse proxy needs it.
- Why not chosen: attractive engineering, but it trades ecosystem alignment — the single biggest
  operational asset for a solo operator — for security gains this threat model doesn't demand.

### Option D — Plain `docker run` scripts

- Summary: shell scripts in the repo that `docker run` each container with the right flags.
- Pros:
  - Zero additional tooling; totally transparent.
- Cons:
  - Imperative, not declarative: scripts describe *actions*, so current state must be torn down
    and rebuilt by hand and drift is invisible.
  - Networks, dependencies and multi-container services (app + database) become fragile
    hand-rolled logic — reimplementing Compose badly.
  - Unreviewable sprawl of flags versus a structured, diffable YAML document.
- Why not chosen: fails the ADR-0002 requirement that the repo declare desired state rather than
  record commands.

## Decision

We will use **Docker Compose (v2 plugin)** as the orchestrator:

- **One `compose.yaml` per service directory** under `services/`; the file name is always
  `compose.yaml` (not `docker-compose.yml`).
- Each service is deployed and lifecycled independently with `docker compose` from its own
  directory.
- Images are version-pinned; storage is bind mounts only ([ADR-0006](0006-bind-mount-strategy.md));
  inter-service HTTP flows over the external `proxy` network
  ([ADR-0009](0009-caddy-reverse-proxy.md)).
- No Swarm mode, no Kubernetes, at single-node scale.

## Pros

- Near-zero orchestrator overhead — every megabyte of the Pi's RAM goes to services.
- One small, universally documented YAML file per service; upstream projects publish Compose
  examples that apply almost verbatim.
- Per-service blast radius: `docker compose up/down` in one directory cannot touch neighbors.
- Minimal concept count keeps the platform operable from memory after months away, and keeps
  runbooks short.

## Cons

- No reconciliation loop: Compose applies state only when invoked. Drift between repo and
  runtime is undetected until the next `docker compose up` (mitigated by the ADR-0002 workflow,
  not by tooling).
- No cross-service dependency graph: startup ordering between services (e.g. proxy before apps)
  is convention plus restart policies, not a managed guarantee.
- Restart-on-failure is the only self-healing; a wedged container needs a human.
- Skills ceiling: operating Compose teaches less than operating k3s would.
- Ten services means ten compose invocations for fleet-wide operations unless wrapped in scripts.

## Consequences

- Repository structure is fixed: `services/<name>/compose.yaml` becomes the unit of deployment,
  review and documentation.
- Shared resources that Compose won't own — the external `proxy` network, `/srv/dahouselab`
  directories — must be created by bootstrap runbooks and documented as prerequisites.
- Fleet-wide helpers (update-all, backup hooks) will be thin scripts iterating service
  directories; they must stay thin or this ADR is being circumvented.
- A future multi-node move is a migration, not an upgrade: compose files translate to Kubernetes
  manifests reasonably well, but nothing carries over automatically.

## Operational impact

- Standard loop per service: edit `compose.yaml` in repo → commit → pull on host →
  `docker compose up -d` in the service directory.
- Logs via `docker compose logs`, status via `docker compose ps`; monitoring (Uptime Kuma)
  covers what Compose does not watch.
- Docker Engine + Compose plugin updates are a host maintenance item
  ([ADR-0003](0003-docker-first.md)).

## Security considerations

- Compose inherits Docker's root-daemon exposure; compose files are root-equivalent input, so
  only reviewed, repo-tracked files may be applied.
- The shared `proxy` network is a lateral-movement path between app containers; services that
  don't need ingress must not join it.
- `.env` files referenced by compose live outside the repo in `/srv/dahouselab/config/<service>`
  and hold the secrets; their permissions matter more than the compose files'.
- No public exposure changes: only Caddy publishes ports ([ADR-0009](0009-caddy-reverse-proxy.md)).

## Future review

- **When node count > 1, this ADR must be re-examined** — that is the explicit trigger at which
  k3s (Option A) becomes the leading candidate and this decision no longer holds by default.
- If services require managed startup ordering across directories, or drift incidents recur,
  revisit reconciliation tooling before adding scripts on scripts.
- If Compose v2 development stalls upstream, re-evaluate Option C (Podman/Quadlet), whose
  ecosystem gap is closing over time.
