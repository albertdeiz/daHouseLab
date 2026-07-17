# Architecture Decision Records

Every significant engineering decision in daHouseLab is recorded as an ADR: the context, the
alternatives that were seriously considered, the decision, and its consequences.

## Why ADRs

Five years from now, the code will show *what* was built; only ADRs preserve *why*. They prevent
re-litigating settled questions, make reversals deliberate (a new ADR superseding the old), and
give any future operator — human or AI — the reasoning needed to change the system safely.

## Rules

- One decision per ADR. Numbered sequentially, never renumbered, never deleted.
- Status lifecycle: `Proposed → Accepted → (Deprecated | Superseded by ADR-NNNN)`.
- A superseded ADR stays in place with its status updated and a link to its successor.
- Filename: `NNNN-kebab-title.md`. Write new ADRs from [`TEMPLATE.md`](TEMPLATE.md).
- An ADR is written **before** the change it describes is implemented.

## When is a decision "architectural"?

Write an ADR when a choice is expensive to reverse, constrains future choices, affects security
or data durability, or would make a reviewer ask "why did you do it this way?". When in doubt,
write it — a short ADR is cheap; a forgotten rationale is not.

## Index

| ADR                                                        | Title                          | Status   |
| ---------------------------------------------------------- | ------------------------------ | -------- |
| [0001](0001-documentation-first.md)                        | Documentation First            | Accepted |
| [0002](0002-infrastructure-as-code.md)                     | Infrastructure as Code         | Accepted |
| [0003](0003-docker-first.md)                               | Docker First                   | Accepted |
| [0004](0004-docker-compose.md)                             | Docker Compose as Orchestrator | Accepted |
| [0005](0005-raspberry-pi-platform.md)                      | Raspberry Pi as Initial Platform | Accepted |
| [0006](0006-bind-mount-strategy.md)                        | Bind Mount Strategy            | Accepted |
| [0007](0007-git-as-source-of-truth.md)                     | Git as Source of Truth         | Accepted |
| [0008](0008-configuration-data-separation.md)              | Configuration/Data Separation  | Accepted |
| [0009](0009-caddy-reverse-proxy.md)                        | Caddy as Reverse Proxy         | Accepted |
| [0010](0010-tailscale-remote-access.md)                    | Tailscale for Remote Access    | Accepted |
| [0011](0011-dns-01-tls-certificates.md)                    | TLS via DNS-01 with Cloudflare DNS | Accepted |
| [0012](0012-layered-environment-files.md)                  | Layered Environment Files      | Accepted |
