# AI Prompts

Reusable prompts and context documents for operating on this repository with AI assistants.

This repository is deliberately **AI-friendly**: consistent structure, explicit conventions and
self-contained documentation mean an AI assistant can be a competent operator. This directory
makes that collaboration reproducible instead of ad-hoc.

## Scope

| Content              | Purpose                                                            |
| -------------------- | ------------------------------------------------------------------ |
| Foundation prompts   | The master prompts used to establish repository standards           |
| Task prompts         | Reusable prompts: scaffold a service, review compose files, audit security, draft an ADR |
| Context documents    | Condensed platform context to prime an assistant at session start   |

## Rules

- Prompts are versioned like code: improve them in place, note significant changes at the top.
- A good prompt states the **role**, the **constraints** (link the [standards](../standards/README.md)),
  and the **definition of done**.
- Never paste secrets, real hostnames/IPs you consider private, or tokens into prompts —
  the same rules as Git apply to AI conversations.
- If an assistant produces a decision, it still becomes an [ADR](../decisions/); if it produces a
  procedure, it still becomes a [runbook](../runbooks/). AI output follows the same standards as
  human output.
