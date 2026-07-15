# Documentation Conventions

## Why

Documentation is the primary deliverable of this repository. These conventions ensure every
document serves its reader — usually me, years later, possibly mid-incident.

## Document types

| Type          | Location                     | Template                                       | Answers                    |
| ------------- | ---------------------------- | ---------------------------------------------- | -------------------------- |
| ADR           | `docs/decisions/`            | [`TEMPLATE.md`](../decisions/TEMPLATE.md)      | Why did we choose X?       |
| Runbook       | `docs/runbooks/`             | [`TEMPLATE.md`](../runbooks/TEMPLATE.md)       | How do I safely do X?      |
| Standard      | `docs/standards/`            | This directory's existing docs                 | What convention governs X? |
| Topic doc     | `docs/<domain>/`             | Freeform, `why → what → how → tradeoffs`       | How does domain X fit together? |
| Service doc   | `services/<name>/docs/`      | [`/templates/service`](../../templates/service/) | How does service X work here? |
| Directory README | Everywhere                | Purpose + contents table + rules               | What is this directory?    |

## The four questions

Every substantive document answers, in order:

1. **Why** — the reasoning and the problem being solved. Always first.
2. **What** — the chosen design/procedure/convention.
3. **How** — concrete steps, examples, commands.
4. **Tradeoffs** — what was given up, known limitations, when to revisit.

A document that only answers "how" is a snippet, not documentation.

## Writing rules

- Write for an engineer with zero context and a broken system: assume stress, not stupidity.
- State facts that expire (versions, IPs, sizes) in **one** authoritative place and link to it.
- Every claim about behavior should be verifiable: include the command that proves it.
- Date things that decay: reviews, exceptions, archived items (`YYYY-MM-DD`).
- English for all documentation (consistency with upstream ecosystems and tooling).
- Update docs in the same commit as the change they describe — documentation debt is technical debt.

## Cross-linking

- Link ADR ↔ runbook ↔ standard whenever they touch the same subject.
- Every service README links: its ADRs, its runbooks, its upstream documentation.
- Broken relative links are defects; check them when moving files.

## Review triggers

Re-read (and re-date) a document when:

- The component it describes changes in any user-visible way.
- A runbook execution deviates from the written procedure (fix the runbook immediately).
- An ADR's "Future review" condition is met.
