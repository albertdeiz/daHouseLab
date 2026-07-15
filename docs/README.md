# Documentation

Documentation is the most important deliverable in daHouseLab. The rule is absolute:
**nothing exists without documentation**, and documentation always answers *why* before *how*.

The goal is long-term maintainability: anyone — including my future self, or an AI assistant —
must be able to understand, operate, recover and evolve the entire infrastructure using only
this repository.

## Map

| Directory                        | Contents                                                          |
| -------------------------------- | ------------------------------------------------------------------ |
| [`architecture/`](architecture/) | Vision, principles, system design, hardware strategy               |
| [`decisions/`](decisions/)       | Architecture Decision Records (ADRs) — the *why* behind everything  |
| [`runbooks/`](runbooks/)         | Step-by-step operational procedures — the *how* for humans          |
| [`standards/`](standards/)       | Engineering handbook: naming, conventions, templates                |
| [`services/`](services/)         | Cross-cutting service documentation (inventory, dependencies)       |
| [`network/`](network/)           | Network topology, IP plan, DNS, reverse proxy routing               |
| [`storage/`](storage/)           | Storage layout, filesystems, mount points, capacity planning        |
| [`security/`](security/)         | Security model, secrets handling, hardening, exposure policy        |
| [`backup/`](backup/)             | Backup strategy, retention, restore expectations (RPO/RTO)          |
| [`operations/`](operations/)     | Day-2 operations: maintenance, monitoring, update policy            |
| [`roadmap/`](roadmap/)           | Planned evolution of the platform                                   |
| [`ai-prompts/`](ai-prompts/)     | Context documents and prompts for AI-assisted operations            |

Per-service implementation documentation lives next to each service in
[`/services/<name>/docs/`](../services/) — close to the component it describes.
Platform-level building blocks are documented in [`/infrastructure/`](../infrastructure/).

## Reading order

For a first end-to-end read:

1. [`architecture/`](architecture/) — why the platform exists and its shape
2. [`standards/`](standards/) — the conventions everything follows
3. [`network/`](network/), [`storage/`](storage/), [`security/`](security/) — the domains
4. [`decisions/`](decisions/) — the reasoning record
5. [`runbooks/`](runbooks/) — the procedures
6. [`backup/`](backup/), [`operations/`](operations/) — keeping it alive
7. [`roadmap/`](roadmap/) — where it goes next

## Which document type do I write?

| Situation                                            | Write a…                          |
| ---------------------------------------------------- | --------------------------------- |
| Choosing between technologies or approaches          | [ADR](decisions/TEMPLATE.md)      |
| A procedure a human performs on the infrastructure   | [Runbook](runbooks/TEMPLATE.md)   |
| A convention every service/document must follow      | [Standard](standards/README.md)   |
| Explaining how a deployed service works              | Service `docs/` (see [service template](../templates/service/)) |
| Describing how a whole domain fits together          | Topic doc (`network/`, `storage/`, …) |

## Rules

- Every directory has a `README.md` stating its purpose.
- Every document explains **why → what → how → tradeoffs**, in that order.
- Every architectural decision becomes an ADR. Every manual operation becomes a runbook.
- Prefer tables, checklists and Mermaid diagrams over prose.
- Update documentation in the same commit as the change it describes.
- If a manual procedure is performed twice, it becomes a runbook.
  If a runbook is executed monthly, it becomes a script in [`/scripts`](../scripts/).
