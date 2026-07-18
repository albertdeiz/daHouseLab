# Infrastructure Configs

Version-controlled configuration **templates and files** for platform components — the
configuration that is authored by hand and reviewed in Git, as opposed to runtime-generated
configuration (which lives in `${CONFIG_ROOT}` on the host, outside Git).

| Belongs here                                   | Does not belong here                          |
| ---------------------------------------------- | --------------------------------------------- |
| Caddyfile (reverse proxy routing)              | TLS certificates Caddy generates              |
| `homepage/` (dashboard YAML — tiles, widgets)  | Databases, caches, application state          |
| Hand-written config for platform components    | Rendered output with real secrets             |
| Config *templates* rendered at deploy time     | Runtime-generated config (lives in `${CONFIG_ROOT}`) |

Rules:

- Files here are mounted into containers **read-only** (see
  [bind mount standard](../../docs/standards/storage-and-bind-mounts.md), rule 5).
- No secrets, ever — secrets are injected via `.env` on the host
  ([environment standard](../../docs/standards/environment-variables.md)).
- Every file here is referenced by at least one compose file or runbook; orphans get archived.
