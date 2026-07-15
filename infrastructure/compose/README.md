# Infrastructure Compose

Base and shared Docker Compose definitions that are platform-scoped rather than service-scoped.

Examples of what belongs here:

- A platform stack that must exist before any service (if one emerges)
- Shared compose fragments included by services via `include:` (use sparingly — a service should
  remain readable standalone)

Most compose files do **not** belong here: each service owns its own
`services/<name>/compose.yaml` per the [service structure standard](../../docs/standards/service-structure.md).

Currently empty by design — populated only when a genuinely shared definition appears.
