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

## File handling

| File            | In Git | Purpose                                                        |
| --------------- | ------ | --------------------------------------------------------------- |
| `.env.example`  | Yes    | Template: every variable, documented, with safe defaults or empty |
| `.env`          | Never  | Real values, host-only, `chmod 600`, owner `root` or the deploy user |

Rules:

- Every service ships a `.env.example` listing **all** variables it consumes — a variable not in
  the template does not exist.
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
