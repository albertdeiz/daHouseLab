# <service-name>

<!--
  TEMPLATE — copy this directory to services/<name>/ and replace every <placeholder>.
  Required sections and their content: docs/standards/service-structure.md
  Delete this comment block when done.
-->

One-paragraph summary: what this service is and **why it is part of the platform**.

## Quick reference

| Field         | Value                                          |
| ------------- | ---------------------------------------------- |
| Image         | `<image>:<pinned-version>`                     |
| URL           | `https://<name>.${DOMAIN}`                     |
| Networks      | `proxy`, `<name>_internal`                     |
| Config path   | `${CONFIG_ROOT}/<name>`                        |
| Data path     | `${DATA_ROOT}/<name>`                          |
| Backup        | yes / no — <what and why>                      |
| Category      | infrastructure / productivity / media / security / monitoring |

## Dependencies

- `proxy` network exists ([infrastructure/networks](../../infrastructure/networks/README.md))
- <other services, host mounts, prior runbooks>

## Deployment

Follow the runbook: [deploy-<name>](../../docs/runbooks/deploy-<name>.md).

## Configuration

- Environment: globals via the `.env` symlink ([ADR-0012](../../docs/decisions/0012-layered-environment-files.md));
  service layer in [`.env.service.example`](.env.service.example) — copy to `.env.service` and fill in.
- <Where non-env configuration lives and how it is managed.>

Details: [`docs/`](docs/README.md).

## Data

What lives in `${DATA_ROOT}/<name>`, its structure, and expected growth.

## Backup & restore

- What is backed up and how (dump vs file copy), per [`docs/backup/`](../../docs/backup/README.md)
- Restore: [restore-from-backup](../../docs/runbooks/restore-from-backup.md) + service specifics

## Operations

- Health: `docker compose ps` shows `healthy`; canonical URL responds
- Logs: `docker compose logs -f <name>`
- Known failure modes: <symptom → action>

## References

- Upstream documentation: <url>
- Related ADRs: <links>
