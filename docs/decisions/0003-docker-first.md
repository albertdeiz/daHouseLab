# ADR-0003: Docker First

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0002, ADR-0004, ADR-0005, ADR-0006, ADR-0010 |

## Context

The platform must be reproducible from this repository ([ADR-0002](0002-infrastructure-as-code.md))
and must survive a hardware migration from the Raspberry Pi 4 to a Mini PC
([ADR-0005](0005-raspberry-pi-platform.md)) without re-engineering. Services planned for the
platform (Nextcloud, Immich, Vaultwarden, Paperless-ngx, monitoring) have conflicting dependency
stacks — different PHP, Python, Node and database versions — that are unmanageable when installed
side by side on one Debian-family host.

Every package installed on the host is state that must be captured, upgraded and migrated by
hand. The fewer things the host *is*, the closer it gets to cattle: a disposable machine defined
entirely by the repo.

## Problem

What is the standard execution environment for applications on this platform — and what, exactly,
is allowed to run directly on the host?

## Alternatives considered

### Option A — Bare-metal installs

- Summary: install each application on the host via apt, pip, or upstream install scripts.
- Pros:
  - No abstraction layer; simplest mental model per service and no container overhead.
  - Full access to hardware and host services.
- Cons:
  - Dependency conflicts across services on one host are inevitable and compounding.
  - Application state smears across `/etc`, `/var`, `/opt`, `/home`; capture in the repo is
    hopeless, violating [ADR-0002](0002-infrastructure-as-code.md).
  - Upgrades and removals are irreversible in practice; the host rots.
- Why not chosen: irreproducible by construction. This is the snowflake host that ADR-0002 exists
  to prevent.

### Option B — Virtual machines (Proxmox)

- Summary: run Proxmox VE on the hardware; one VM (or a few) per concern.
- Pros:
  - Strong isolation; per-service kernels; snapshot and migration tooling is excellent.
  - Industry-standard homelab path with a large community.
- Cons:
  - Raspberry Pi 4 with 8 GB RAM cannot afford per-VM kernel and memory overhead for ~10 services.
  - Proxmox on ARM64 is not a first-class, supported target.
  - Adds a hypervisor layer to manage, back up and document — a platform under the platform.
- Why not chosen: resource cost and ARM64 support make it a poor fit for the current hardware;
  it solves isolation problems this platform does not have.

### Option C — LXC system containers

- Summary: lightweight OS containers per service (LXC/LXD/Incus).
- Pros:
  - Near-native performance with VM-like semantics; cheap on RAM.
  - Good fit for "pet" containers that behave like small servers.
- Cons:
  - Each container is a small OS to patch and configure — the snowflake problem multiplied, not
    solved.
  - The self-hosting ecosystem publishes OCI images, not LXC templates; every service becomes a
    manual install inside a container.
  - Weaker declarative story than Compose for defining app + mounts + networks in one file.
- Why not chosen: LXC containerizes the *host* pattern; we want to containerize *applications*.
  It inherits Option A's reproducibility problem inside each container.

### Option D — Nix / NixOS

- Summary: declarative host configuration with Nix; services as NixOS modules.
- Pros:
  - The strongest reproducibility guarantee of any option; whole-system rollbacks.
  - Elegant fit with the IaC principle — the entire host in one expression.
- Cons:
  - Steep, ongoing learning curve; debugging failures requires Nix expertise the operator does
    not yet have — dangerous for a platform that must be fixable at 11pm.
  - Smaller ecosystem for self-hosted apps than Docker images; some services would need packaging.
  - NixOS on Raspberry Pi is workable but off the mainstream support path.
- Why not chosen: maximizes reproducibility but also maximizes operator risk today. Docker
  images + Git achieve sufficient reproducibility with vastly more transferable knowledge.

## Decision

We will run **all applications in Docker containers**. The host is kept minimal:

- Nothing is installed on the host except **Docker Engine (with the Compose plugin)**,
  **Tailscale**, and base OS tooling (git, openssh, curl, editors, filesystem utilities).
- Tailscale is the sole sanctioned host-level service exception: it needs host networking and
  the kernel WireGuard path to provide access *to* the host itself, including when Docker is
  down ([ADR-0010](0010-tailscale-remote-access.md)).
- Images are version-pinned; state reaches the host only through bind mounts under
  `/srv/dahouselab` ([ADR-0006](0006-bind-mount-strategy.md)).
- Only the Caddy container publishes host ports; all other apps join the external `proxy`
  network ([ADR-0009](0009-caddy-reverse-proxy.md)).

## Pros

- Dependency isolation: each service ships its own stack; conflicts disappear.
- The service definition is one text file in the repo — reproducibility falls out for free.
- Hardware independence: the same compose files run on the Pi and the future Mini PC, provided
  images are multi-arch.
- Add/remove services without residue on the host; the host stays boring and rebuildable.

## Cons

- ARM64 constrains image choice: some upstream images are amd64-only, forcing alternatives or
  exclusion ([ADR-0005](0005-raspberry-pi-platform.md)).
- The Docker daemon is a single point of failure and runs as root; a daemon bug or bad upgrade
  takes down every service at once.
- An abstraction layer to debug: networking, storage and logs all pass through Docker's
  indirection.
- Container-native assumptions (ephemeral filesystems, env-var config) fit some legacy apps
  poorly.
- Image supply chain becomes a dependency: registry availability and upstream image hygiene are
  now operational concerns.

## Consequences

- Every service decision starts with "is there a maintained multi-arch image?" — a hard gate.
- Orchestration must be chosen ([ADR-0004](0004-docker-compose.md)) and a persistence strategy
  defined ([ADR-0006](0006-bind-mount-strategy.md)); both are direct children of this decision.
- Host bootstrap runbook shrinks to: OS, Docker, Tailscale, mounts, clone repo.
- Anything that cannot run in a container must justify itself in a new ADR; Tailscale's
  exception is documented, not precedent.

## Operational impact

- Day-to-day operations become uniform: `docker compose pull/up/down/logs` regardless of service.
- Upgrades are image tag bumps in the repo, applied via the ADR-0002 loop; rollback is reverting
  the tag.
- Docker Engine itself joins the (short) list of host packages to patch.
- Debugging adds a step (exec into containers, inspect networks) but the skills apply to every
  service identically.

## Security considerations

- The Docker daemon is root-equivalent; anyone or anything that can talk to the socket owns the
  host. The socket must never be mounted into a container without an explicit ADR.
- Containers provide isolation but share the kernel — weaker than VMs; kernel and Docker updates
  are security-critical.
- Image provenance matters: pinned versions from reputable publishers only; pinning also
  prevents silent supply-chain drift via `latest`.
- Default no-published-ports posture ([ADR-0009](0009-caddy-reverse-proxy.md)) means a
  compromised app is reachable only via the `proxy` network, limiting blast radius.

## Future review

- At Mini PC migration (amd64): the multi-arch constraint relaxes; no change to this ADR expected.
- If node count > 1 or isolation requirements grow (untrusted workloads), revisit Option B/VMs.
- If the operator's Nix competence matures and the ecosystem gap closes, Option D may be
  re-evaluated for the *host layer* only.
- If a required service has no viable container path, that service triggers a scoped exception
  ADR rather than eroding this one.
