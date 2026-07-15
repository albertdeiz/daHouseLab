# daHouseLab — AI Assistant Context

This repository is the single source of truth for a personal homelab (IaC). It is deliberately
self-documenting: **read before acting, follow the standards exactly.**

## Read first

1. `docs/standards/README.md` — the engineering handbook (naming, compose rules, storage, env vars)
2. `docs/runbooks/README.md` — every operation has a runbook; deployment order lives here
3. `docs/decisions/README.md` — 11 ADRs; do not re-litigate settled decisions, supersede them

## Hard rules

- Documentation first: no change without updating docs in the same commit.
- Never commit secrets, data, certs, or runtime files (see `.gitignore` and ADR-0007).
- All persistence is bind mounts via `${CONFIG_ROOT}`/`${DATA_ROOT}` — never named volumes.
- Only Caddy publishes ports; apps join the external `proxy` network; DBs on internal networks.
- Compose files are `compose.yaml`, images version-pinned, every service has a healthcheck
  and `dahouselab.*` labels (`docs/standards/docker-compose-conventions.md`).
- New services: copy `templates/service/`, follow `docs/standards/service-structure.md`.

## Live environment

- Host: Raspberry Pi 4 (`daHouse`, Debian 13 trixie, arm64) — repo at `/opt/dahouselab`,
  deployed services under `services/`, domain `dahub.casa` (Cloudflare DNS, DNS-01 TLS, ADR-0011).
- Deploy pattern: author in Git → commit/push → `git pull` on the host → follow the service's
  runbook. Never edit files directly on the host.
- The human operator runs all `sudo` and interactive steps; assistants never handle secrets.
