# Architecture

This section documents the overall architecture of **daHouseLab**: the long-term vision,
the engineering principles, and the shape of the system — independently from implementation
details, which live in [`/infrastructure`](../../infrastructure/) and [`/services`](../../services/).

It answers questions such as:

- Why does the homelab exist?
- Which engineering principles guide its evolution?
- What does the system look like, and why is it shaped that way?
- How should future services and hardware integrate into the platform?

The individual decisions that produced this shape are recorded as ADRs in
[`../decisions/`](../decisions/).

## Documents

| Document                             | Purpose                                     |
| ------------------------------------ | ------------------------------------------- |
| [`vision.md`](vision.md)             | Long-term vision and success criteria       |
| [`principles.md`](principles.md)     | Engineering principles                      |
| [`overview.md`](overview.md)         | High-level system architecture — start here |
| [`hardware.md`](hardware.md)         | Hardware strategy and phases                |
| [`future-plans.md`](future-plans.md) | Long-term architectural evolution           |

## Rules

- Diagrams are authored as Mermaid whenever possible so they diff in Git; binary assets live in
  [`/assets`](../../assets/).
- When architecture changes, the diagram and the relevant ADR change in the same commit.
- This directory stays technology-agnostic where possible; product names appear only where a
  decision has been recorded in an ADR.
