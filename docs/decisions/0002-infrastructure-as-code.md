# ADR-0002: Infrastructure as Code

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0001, ADR-0003, ADR-0004, ADR-0005, ADR-0007 |

## Context

The platform runs on a single Raspberry Pi 4 ([ADR-0005](0005-raspberry-pi-platform.md)) with a
planned migration to a Mini PC. Hardware at this tier fails: SD cards corrupt, power supplies
brown out, USB SSDs die. The services hosted here (files, photos, passwords, documents) carry
real durability expectations, so "rebuild the box" must be a routine procedure, not a research
project.

A homelab configured by hand accumulates snowflake state — packages installed during a late-night
debugging session, config files edited in place, firewall rules nobody remembers adding. Such a
host cannot be rebuilt, only archaeologically restored. [ADR-0001](0001-documentation-first.md)
already requires that everything be documented; this ADR decides *where the authoritative
definition of the platform lives*.

## Problem

Should the platform be defined declaratively in a version-controlled repository such that it is
reproducible from that repository alone, or administered directly on the host?

## Alternatives considered

### Option A — Manual administration

- Summary: SSH in, install and configure by hand, keep notes as needed.
- Pros:
  - Zero up-front investment; every tutorial on the internet assumes this model.
  - Maximum flexibility for one-off fixes.
- Cons:
  - The host becomes an unreproducible snowflake; a disk failure means total rebuild from memory.
  - No history: no way to answer "what changed last Tuesday" or to roll back.
  - Directly contradicts [ADR-0001](0001-documentation-first.md) — reality and documentation
    drift apart with no mechanism to reconcile them.
- Why not chosen: unacceptable recovery story for a platform holding personal data on failure-prone
  hardware.

### Option B — Configuration management only (Ansible) without repo-first discipline

- Summary: automate host setup with Ansible playbooks, but treat the playbooks as tooling that
  chases the host's actual state rather than as the single source of truth.
- Pros:
  - Real automation for host bootstrap (users, packages, Docker install, mounts).
  - Idempotent, well understood, agentless.
- Cons:
  - Without repo-first discipline, playbooks codify *some* of the host and drift covers the rest;
    the worst of both worlds — automation that lies.
  - A second toolchain (Python, Ansible versions, inventories) to maintain for a one-node fleet.
  - Encourages host-level installs, which [ADR-0003](0003-docker-first.md) forbids; most of what
    Ansible would manage is deliberately out of scope.
- Why not chosen: the tool is fine; the discipline is the decision. Ansible without repo-first
  rigor solves the wrong problem, and with only one node the host bootstrap is small enough for a
  documented runbook. Ansible remains a candidate *implementation* of that runbook later.

### Option C — Managed / cloud services

- Summary: replace self-hosting with SaaS or a cloud VPS with managed offerings (managed
  Nextcloud, hosted password manager, etc.).
- Pros:
  - Reproducibility and availability become someone else's problem.
  - Professional operations, offsite by construction.
- Cons:
  - Recurring cost that grows with data volume; photos alone make this expensive.
  - Personal data custody moves to third parties, defeating a core purpose of the homelab.
  - Nothing is learned; the lab stops being a lab.
- Why not chosen: conflicts with the project's purpose (data sovereignty and learning). Cloud
  remains a fallback for individual services if self-hosting one proves untenable
  (see [ADR-0005](0005-raspberry-pi-platform.md) for the platform-level version of this tradeoff).

## Decision

We will define the **entire platform in this Git repository**, checked out on the host at
`/opt/dahouselab`:

- The platform must be reproducible from a clone of this repo plus restored data from
  `/mnt/backups`. If a rebuild would need anything else, that is a defect.
- **No manual snowflake configuration.** Host state not derivable from the repo is forbidden.
- Where a step cannot yet be automated (OS install, disk formatting, Tailscale enrollment), it
  must live in a runbook under `docs/runbooks/`, marked as pending automation. Runbooks are the
  authorized escape hatch, not an exemption.
- Git is the single source of truth for desired state ([ADR-0007](0007-git-as-source-of-truth.md)
  details the workflow).

## Pros

- Full rebuild is a bounded, tested procedure: flash OS, run bootstrap runbook, clone repo,
  restore data, `docker compose up`.
- Every change has history, authorship and a diff; rollback is `git revert`.
- The Mini PC migration becomes an execution of existing runbooks rather than a re-design.
- Review (human or AI) happens on text, before changes reach the host.

## Cons

- Higher friction for every change: edit repo, commit, pull on host — even for a one-line tweak.
- Real risk of drift anyway: nothing *technically* stops an SSH edit; the guarantee is
  discipline, and periodic reconciliation is manual work.
- Some state genuinely resists capture (Tailscale node keys, disk serials, DHCP reservations on
  the router) and lives awkwardly in runbook prose.
- Runbooks-pending-automation can become runbooks-forever; the escape hatch needs policing.

## Consequences

- The repo layout must mirror the platform: one directory per service with its `compose.yaml`
  ([ADR-0004](0004-docker-compose.md)), runbooks for everything manual.
- Runtime config (`/srv/dahouselab/config/<service>`) and data (`/srv/dahouselab/data/<service>`)
  live *outside* the repo by design; the repo defines them, it does not contain them
  ([ADR-0008](0008-configuration-data-separation.md)).
- Secrets need a story that keeps them out of Git while keeping the platform reproducible.
- Any tool choice from here on is evaluated partly on "can it be driven from files in this repo".

## Operational impact

- The operational loop is: change in repo → commit → pull at `/opt/dahouselab` → apply. SSH
  sessions that mutate state outside this loop are incidents.
- A periodic drift check (compare running state to repo) joins the maintenance schedule.
- Disaster recovery drills exercise the rebuild runbooks, not backups alone.

## Security considerations

- The repo becomes a high-value target: it describes the whole platform. It must remain private,
  and its remotes are part of the trust boundary.
- Secrets (API keys, passwords) must never be committed; `.env` files live in
  `/srv/dahouselab/config/<service>` and are referenced, not stored, by the repo.
- Version history is an audit log — useful forensically, but it also means an accidentally
  committed secret persists in history and must be treated as compromised.

## Future review

- When node count > 1, revisit Option B: configuration management or similar tooling becomes
  justified for host bootstrap across machines.
- If runbook-documented manual steps stop shrinking over time, revisit the automation backlog
  explicitly.
- If a rebuild drill fails to complete from repo + backups alone, this ADR's guarantee is broken
  and the gap must be closed before new services are added.
