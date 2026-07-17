# vaultwarden

Bitwarden-compatible password manager ([vaultwarden](https://github.com/dani-garcia/vaultwarden))
at `https://vault.dahub.casa`. It centralizes every credential the platform and its operator own —
which makes it **the highest-value target on the host**: every security step in its runbook is
mandatory, and its data directory is the most critical backup on the platform.

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `vaultwarden/server:1.34.3`                    |
| URL           | `https://vault.${DOMAIN}`                      |
| Networks      | `proxy`                                        |
| Config path   | — (single app dir; see Data)                   |
| Data path     | `${DATA_ROOT}/vaultwarden` (SQLite + keys + attachments, one mount — documented deviation from the two-mount rule), mode `700` |
| Backup        | yes — **most critical on the platform** (SQLite: dump/stop-copy, never live file copy) |
| Category      | security                                       |

## Dependencies

- `proxy` network + Caddy with working TLS — **HTTPS is strictly required** (clients refuse
  plain HTTP; web-vault crypto needs a secure context)
- Uptime Kuma deployed, so this service is monitored from day one

## Deployment

Follow the runbook: [deploy-vaultwarden](../../docs/runbooks/deploy-vaultwarden.md).

**Deliberate deviation (2026-07-17):** deployed *without* `ADMIN_TOKEN`, so the `/admin` panel is
entirely disabled — safer than managing a token with no password manager in place yet
(chicken-and-egg). To enable later: generate + argon2-hash a token per runbook step 2, store the
plaintext *inside the vault*, add the hash to `.env`, `docker compose up -d`.

## Configuration

- Environment: see [`.env.example`](.env.example). Key settings: `SIGNUPS_ALLOWED` (true only
  during first-account creation, then false forever) and the container-level `DOMAIN` override in
  `compose.yaml` (full URL, required by WebAuthn/attachments).
- Everything else is defaults; changes go through `.env` + `docker compose up -d`.

## Data

`${DATA_ROOT}/vaultwarden`: `db.sqlite3` (the vault), `rsa_key*` (auth tokens signing),
`attachments/`, `sends/`. Small (MBs) but irreplaceable. Mode `700`.

## Backup & restore

- SQLite via `sqlite3 db.sqlite3 ".backup ..."` or stop-copy-start — never a live copy
  ([execute-backup](../../docs/runbooks/execute-backup.md)); `rsa_key*` and `attachments/` ride
  the file backup.
- Restore: [restore-from-backup](../../docs/runbooks/restore-from-backup.md).
- **The master password is unrecoverable by design** — no backup helps if it is lost.

## Operations

- Health: `docker compose ps` → `healthy`; `curl -fsS https://vault.${DOMAIN}/alive` → `200`
- Logs: `docker compose logs -f vaultwarden`
- Known failure modes: clients refuse connection → TLS problem at Caddy, never bypass with HTTP;
  registration unexpectedly open → `SIGNUPS_ALLOWED` not applied, recreate with `up -d` (not `restart`).

## References

- Upstream documentation: <https://github.com/dani-garcia/vaultwarden/wiki>
- Related: [ADR-0009](../../docs/decisions/0009-caddy-reverse-proxy.md),
  [ADR-0011](../../docs/decisions/0011-dns-01-tls-certificates.md),
  [docs/security](../../docs/security/README.md)
