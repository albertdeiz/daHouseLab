# Post-mortem: ingress outage during ADR-0012 env migration

| Field    | Value                                   |
| -------- | ---------------------------------------- |
| Date     | 2026-07-17                               |
| Duration | ~10 minutes (Caddy down → all web UIs unreachable) |
| Impact   | Full ingress outage; Vaultwarden briefly ran without `SIGNUPS_ALLOWED=false` (tailnet-only exposure) |
| Detected | Uptime Kuma → Telegram alerts + migration verification step |

## What happened

The [ADR-0012](../decisions/0012-layered-environment-files.md) migration script ran `git pull -q
2>/dev/null && …` on the Pi. The pull **failed silently** (divergent branches: history had been
rewritten upstream, so the deploy clone could not fast-forward) and the script continued: it
replaced each service's `.env` with the globals symlink while the **old** compose files (single
`env_file: .env`) were still in effect.

Consequences: Caddy restarted with an empty `CLOUDFLARE_API_TOKEN` and crash-looped (no ingress);
Vaultwarden lost its service-specific env and fell back to upstream defaults.

## Root causes

1. **Silenced failure in a mutating sequence** — `-q 2>/dev/null` hid the pull error, and `&&`
   only guarded the log line, not the migration.
2. **History rewrite upstream** — the deploy clone's branch and `origin/main` contained the same
   changes under different hashes, so fast-forward was impossible.

## Resolution

`git reset --hard origin/main` on the Pi (deploy clones hold no unique work by design — verified
before resetting), recreate `.env.service` files, `docker compose up -d` per service. All
services healthy; `SIGNUPS_ALLOWED=false` verified in-container.

## Prevention (applied)

- Pi git config set to `pull.ff only` — divergence now fails loudly instead of silently.
- Lesson recorded: **never silence git output in mutating sequences**; verify the pull landed
  (`git log --oneline -1`) before acting on its result.
- Standing rule reinforced: the Pi checkout is disposable — when in doubt, reset to
  `origin/main`, never merge on the host.

## Follow-ups

- The future `scripts/deploy-service.sh` must gate every mutating step on the previous step's
  exit code and print (not swallow) git output.
