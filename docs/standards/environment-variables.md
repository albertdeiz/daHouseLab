# Environment Variable Conventions

## Why

Environment variables are the boundary between version-controlled infrastructure and
machine-specific reality (paths, domains, secrets). A strict convention keeps that boundary
auditable: everything in Git is a template; everything real lives only on the host.

## Naming

| Rule                | Convention                                     | Example                               |
| ------------------- | ---------------------------------------------- | ------------------------------------- |
| Case                | `UPPER_SNAKE_CASE`                             | `NEXTCLOUD_DB_PASSWORD`               |
| Service variables   | Prefixed with the service name                 | `IMMICH_DB_PASSWORD`, `PAPERLESS_SECRET_KEY` |
| Platform variables  | Global, unprefixed set (defined once, root `.env`) | `TZ`, `PUID`, `PGID`, `DOMAIN`, `HOST_IP` |
| Path roots          | `*_ROOT` suffix                                | `CONFIG_ROOT`, `DATA_ROOT`, `BACKUP_ROOT` |
| Secrets             | Suffix states the kind                         | `*_PASSWORD`, `*_TOKEN`, `*_SECRET`, `*_API_KEY` |
| Booleans            | `true` / `false` lowercase                     | `PAPERLESS_TIKA_ENABLED=true`         |

Reserved global set (single source: root [`.env.example`](../../.env.example)):
`DAHOUSELAB_HOST`, `DAHOUSELAB_ROOT`, `TZ`, `PUID`, `PGID`, `DOMAIN`, `HOST_IP`,
`CONFIG_ROOT`, `DATA_ROOT`, `BACKUP_ROOT`.

## File handling — the layered model ([ADR-0012](../decisions/0012-layered-environment-files.md))

| File                         | In Git | Purpose                                                        |
| ---------------------------- | ------ | --------------------------------------------------------------- |
| `/.env.example` (root)       | Yes    | Template for the platform globals                               |
| `/.env` (root)               | Never  | The **single owner** of all globals — must **never** contain a secret (it feeds every container) |
| `services/<svc>/.env`        | Never  | **Symlink** to the root `.env`, created at deploy (`ln -sf ../../.env .env`) — serves compose interpolation and the globals layer |
| `services/<svc>/.env.service.example` | Yes | Template: the service's own variables, documented          |
| `services/<svc>/.env.service`| Never  | Service-specific values **and secrets**, `chmod 600`            |

Every `compose.yaml` loads both layers, in this order (later overrides earlier):

```yaml
env_file:
  - .env          # platform globals (via symlink)
  - .env.service  # service-specific — overrides globals on collision
```

Rules:

- Every service ships a `.env.service.example` listing **all** service variables it consumes —
  a variable not in the template does not exist.
- Secrets live exclusively in `.env.service` files — one secret reaches exactly one stack.
- **Interpolation rule:** Compose interpolates `${VAR}` inside `compose.yaml` only from the
  literal `.env` (the symlink → globals). Therefore `${VAR}` in compose files may reference
  **globals only**; service-specific values are container-env only (`env_file`). Image tags are
  written literally in compose (pinning convention); values needed inside healthcheck commands
  use `$$VAR` (runtime container-env expansion), never `${VAR}`.
- Templates document each variable with a comment: what it is, how to generate it if secret
  (e.g. `# Generate: openssl rand -base64 32`).
- Secret values never get defaults in templates — an empty value that fails loudly beats a
  default that works silently.
- No secrets in `environment:` blocks of compose files, in shell history, or in documentation
  examples (use `<REDACTED>` placeholders).
- Rotation is a runbook: [rotate-secrets](../runbooks/rotate-secrets.md).

## Tradeoffs

- `.env` files are plaintext on the host — accepted at this scale, mitigated by file permissions
  and full-disk trust in a physically-controlled machine. A secrets manager (e.g. SOPS + age)
  is a documented roadmap candidate; adopting one requires an ADR.
