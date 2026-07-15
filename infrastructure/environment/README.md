# Environment Templates

Global environment templates beyond the root [`.env.example`](../../.env.example).

The root template defines the platform-wide variable set (`TZ`, `PUID`, `DOMAIN`, `*_ROOT`, …).
This directory holds additional environment templates that are platform-scoped but not global —
for example, a shared database credential template consumed by multiple stacks, if one ever emerges.

Rules ([environment standard](../../docs/standards/environment-variables.md)):

- Templates only (`.env.example` / `*.env.template`). Real `.env` files never enter Git.
- Every variable documented with a comment; secret variables ship empty with a generation hint.

Currently empty by design.
