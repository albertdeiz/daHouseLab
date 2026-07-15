# ADR-0001: Documentation First

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0002, ADR-0007, [markdown conventions](../standards/markdown-conventions.md) |

## Context

daHouseLab is a single-operator homelab. There is no team to ask, no on-call rotation, and no
institutional memory beyond what is written down. The platform is touched in bursts — weeks may
pass between operational sessions — and by the next session the operator has reliably forgotten
the details of the last one. The repository at `/opt/dahouselab` is intended to be the complete
description of the platform ([ADR-0002](0002-infrastructure-as-code.md)); an increasing share of
work will also be performed by AI agents, which can only act on what the repository states
explicitly.

Undocumented decisions in this environment do not degrade gracefully. They become mystery
configuration that nobody dares change, which directly contradicts the goal of a platform that
is fully reproducible and safely modifiable.

## Problem

What is the required relationship between documentation and every other artifact in this
repository — is documentation a by-product of the work, or the work itself?

## Alternatives considered

### Option A — Code-first, document later

- Summary: build and configure first; write documentation when things stabilize, "when there is time".
- Pros:
  - Fastest visible progress in the short term.
  - No documentation effort spent on experiments that get thrown away.
- Cons:
  - "Later" empirically never arrives; docs decay into an unordered backlog.
  - Rationale is lost immediately — code shows *what*, never *why*.
  - Docs written after the fact describe the outcome, not the reasoning or the rejected options.
- Why not chosen: this is the default failure mode of every homelab. It optimizes for the first
  month and bankrupts every month after.

### Option B — Wiki outside the repository

- Summary: keep documentation in an external system (hosted wiki, Notion, a self-hosted wiki
  service) separate from the code.
- Pros:
  - Rich editing, search and media handling out of the box.
  - Low friction for quick notes.
- Cons:
  - Docs and code version independently, so they drift; no single commit ties a change to its
    explanation.
  - No review of docs through the same diff workflow as code.
  - If self-hosted, the documentation needed to rebuild the platform lives *on* the platform —
    circular dependency during disaster recovery.
- Why not chosen: separating docs from the repo breaks atomicity (one commit = change + its
  documentation) and creates a recovery-time dependency on the very system being recovered.

### Option C — Minimal README-only

- Summary: one `README.md` per service with setup notes; no ADRs, no runbooks, no standards.
- Pros:
  - Very low overhead.
  - Better than nothing; co-located with the code.
- Cons:
  - No home for cross-cutting reasoning (why Docker, why this hardware, why this network shape).
  - READMEs answer "how do I start it", never "why is it built this way" or "how do I recover it".
  - Scales poorly: ten services means ten inconsistent, partial documents.
- Why not chosen: acceptable for a toy, insufficient for a platform intended to hold personal
  data with real durability requirements.

## Decision

We will treat documentation as the **primary deliverable** of this repository:

- Nothing exists until it is documented. A service, script or configuration without
  documentation is considered incomplete and may not be relied upon.
- Documentation answers **why before how**. Every document leads with reasoning; mechanics
  follow ([markdown conventions](../standards/markdown-conventions.md)).
- Documentation is updated **in the same commit** as the change it describes. A commit that
  changes behavior without touching its documentation is a defective commit.
- Significant decisions are recorded as ADRs before implementation, per
  [the ADR rules](README.md).

## Pros

- Rationale survives arbitrarily long gaps between operational sessions.
- Any operator — the author in two years, or an AI agent today — can modify the system safely
  because the constraints and reasoning are explicit.
- Disaster recovery depends only on a Git clone, not on memory or an external service.
- Docs reviewed as diffs stay accurate, because inaccuracy is visible at review time.

## Cons

- Every change costs more up front; small tweaks carry documentation overhead.
- Discipline is self-enforced — with a single operator there is no reviewer to reject an
  undocumented commit, so the rule erodes silently if not policed.
- Documentation can rot into confident falsehood if the same-commit rule is ever skipped, which
  is worse than admitted ignorance.
- Slows down experimentation; there is a real temptation to prototype outside the repo and lose
  the findings.

## Consequences

- The repository gains a permanent documentation skeleton (`docs/architecture`, `docs/decisions`,
  `docs/runbooks`, `docs/standards`) that every future change must slot into.
- All subsequent ADRs (0002–0010) exist because this ADR mandates them.
- "Definition of done" for any task now includes the docs diff.
- Manual actions performed on the host without a corresponding doc/runbook update are treated as
  incidents, not shortcuts (reinforced by [ADR-0002](0002-infrastructure-as-code.md)).
- Future tooling (linters, CI) should verify structural conventions where possible.

## Operational impact

- Every runbook change, service addition or configuration change includes a documentation edit
  in the same commit; commit review starts with the docs diff.
- Periodic doc audits replace nothing — they are an added maintenance task to catch drift.
- Onboarding a new machine or a new agent starts with `docs/`, not with the compose files.

## Security considerations

- Documentation must never contain secrets; it describes *where* secrets live, not their values.
  This must be checked at commit time like any other file.
- Accurate documentation of the security posture (network shape, exposure, backup paths) is
  itself a security control: undocumented exposure is unaudited exposure.
- Detailed public documentation of a private system would be a map for an attacker; the
  repository is treated as private accordingly.

## Future review

- If the same-commit rule is repeatedly violated in practice, revisit with enforcement tooling
  (pre-commit checks, CI) rather than abandoning the principle.
- If the platform gains a second human operator, revisit the review workflow (docs currently
  assume self-review).
- If documentation volume makes navigation the bottleneck, revisit structure — not the
  documentation-first principle itself.
