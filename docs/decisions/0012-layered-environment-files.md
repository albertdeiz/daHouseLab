# ADR-0012: Layered Environment Files

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-17                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0004](0004-docker-compose.md), [ADR-0007](0007-git-as-source-of-truth.md), [docs/standards/environment-variables.md](../standards/environment-variables.md) |

## Context

Each service is an independent Compose stack ([ADR-0004](0004-docker-compose.md)) with its own
`.env`. The original procedure copied the root `.env` (globals: `TZ`, `PUID`/`PGID`, `DOMAIN`,
`*_ROOT` paths) into every service directory and appended service-specific variables. With four
services deployed, every global value existed in five copies.

Copies drift: changing `DATA_ROOT` (planned SSD migration) or `DOMAIN` would require remembering
every copy, and a stale copy fails silently — the exact failure mode this repository exists to
prevent.

The constraint that shaped the solution: Compose consumes variables at **two distinct moments**:

1. **Interpolation** of `${VAR}` inside `compose.yaml` (volume paths, labels) — read **only**
   from the file literally named `.env` next to the compose file (or the shell).
2. **Container environment** — the `env_file:` directive, which accepts an ordered **list**
   (later files override earlier).

Any design must feed both moments from a single global source.

## Problem

How do services consume shared platform variables from one authoritative file — without
sacrificing per-service secret isolation or stack independence?

## Alternatives considered

### Option A — Status quo: copy root `.env` per service

- Pros: dead simple; each stack fully self-contained.
- Cons: N copies of every global; silent drift on change; already caused redundancy at N=4.
- Why not chosen: drift risk grows with every service; contradicts single-source-of-truth.

### Option B — Multiple `--env-file` flags on every command

- Summary: `docker compose --env-file ../../.env --env-file .env up -d`.
- Pros: no filesystem tricks.
- Cons: every human and script must remember the flags; a forgotten flag half-applies config.
- Why not chosen: convention-by-memory is not a convention.

### Option C — Generated `.env` (sync script merges global + service fragment)

- Pros: keeps plain files; scriptable.
- Cons: reintroduces drift between syncs — editing the global then forgetting the sync is the
  same silent failure with an extra step.
- Why not chosen: automation that must be remembered fails like manual work.

### Option D — Symlinked global + layered `env_file` (chosen)

- Summary: `services/<svc>/.env` is a **symlink** to the root `.env`; service-specific values
  (including secrets) live in `services/<svc>/.env.service`; compose declares
  `env_file: [.env, .env.service]`.
- Pros: interpolation reads current globals through the symlink; container env layers with
  explicit override order; zero duplication; secrets stay per-service; boring, well-known pattern.
- Cons: symlinks are created at deploy time (one extra step); a global edit affects all stacks on
  their next `up -d`.

### Option E — Single platform-wide Compose project

- Pros: one `.env`, native.
- Cons: destroys stack-per-service independence ([ADR-0004](0004-docker-compose.md)).
- Why not chosen: modularity is a founding constraint.

## Decision

We will layer environment files per service:

```text
/opt/dahouselab/.env            # single owner of all platform globals — NEVER contains secrets
services/<svc>/.env             # symlink → ../../.env (created at deploy, not in Git)
services/<svc>/.env.service     # service-specific variables and secrets, chmod 600
```

Every `compose.yaml` declares, in this order:

```yaml
env_file:
  - .env          # platform globals (via symlink)
  - .env.service  # service-specific — overrides globals on collision
```

Templates: the root ships `.env.example`; each service ships `.env.service.example` documenting
only its own variables.

## Pros

- One authoritative file for globals; changes propagate on next `up -d` — no copies to chase.
- Secrets remain isolated per service directory with `600` permissions.
- Interpolation and container env are both served without wrapper scripts or flags.

## Cons

- Deploy gains a symlink step (scripted away in the runbooks).
- All containers receive all global variables (they already did under the copy scheme).
- `ls -la` literacy required: a broken symlink fails interpolation loudly but unfamiliarly.
- `${VAR}` interpolation in compose files can only see globals — service-specific values are
  container-env only. Image tags are therefore written literally in compose (which the pinning
  convention already required), and healthcheck commands use `$$VAR` runtime expansion.

## Consequences

- **New hard rule: the root `.env` must never contain a secret** — it feeds every container.
  Secrets belong exclusively in `.env.service` files.
- Standards, the service template and all deploy runbooks change in the same commit as this ADR.
- Existing services (caddy, homepage, uptime-kuma, vaultwarden) are migrated in place.

## Operational impact

- Deploy procedure: `ln -s ../../.env .env` + create `.env.service` from its example, instead of
  copying and appending.
- After editing the root `.env`, affected stacks need `docker compose up -d` to pick up changes —
  same as before.
- Backup/restore unaffected: symlinks are re-created by deploy, `.env.service` files ride the
  config backup like `.env` did.

## Security considerations

- Secret blast radius shrinks: globals file feeding all containers is guaranteed secret-free;
  each secret reaches exactly one stack.
- `.env.service` inherits every existing rule: never in Git, `chmod 600`, edited only with an
  editor ([rotate-secrets](../runbooks/rotate-secrets.md)).

## Future review

Re-examine if:

- Compose gains native layered interpolation (e.g. multiple implicit env files) — the symlink
  becomes unnecessary.
- The platform adopts a secrets manager (SOPS/age — roadmap), which would absorb `.env.service`.
- Stack count or multi-host layout makes per-host globals diverge.
