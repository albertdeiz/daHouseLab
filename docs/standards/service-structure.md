# Service Structure

## Why

Every service directory is a self-contained, uniformly-shaped unit: anyone who has operated one
service can operate them all, and a new service is a copy of the template plus specifics —
not a design exercise.

## Anatomy

Every directory under `/services` follows exactly this structure
(scaffolded by [`/templates/service`](../../templates/service/)):

```text
services/<name>/
├── README.md          # Front page: what, why, how to operate (see required sections below)
├── compose.yaml       # The deployment — follows docker-compose-conventions.md
├── .env.service.example  # The service's own variables, documented (globals come via the .env symlink — ADR-0012)
├── docs/              # Deep documentation (architecture, config reference, decisions)
│   └── README.md
└── scripts/           # Service-specific automation (backup, restore, maintenance)
    └── (optional; shared logic belongs in /scripts)
```

## Required README sections

Every service `README.md` must contain, in order:

| Section          | Content                                                              |
| ---------------- | -------------------------------------------------------------------- |
| Title + summary  | What the service is and **why it is part of the platform**            |
| Quick reference  | Table: image + pinned version, URL, port, networks, config/data paths, backup: yes/no |
| Dependencies     | What must exist first (networks, other services, host mounts)         |
| Deployment       | Link to its runbook in `docs/runbooks/deploy-<name>.md`               |
| Configuration    | What is configurable, where; link to `.env.service.example` and `docs/` |
| Data             | Exactly what lives in `${DATA_ROOT}/<name>` and its growth profile    |
| Backup & restore | What gets backed up, how, and the restore procedure link              |
| Operations       | Health check command, log access, known failure modes                 |
| References       | Upstream docs, related ADRs                                           |

## Lifecycle rules

- **Add:** copy the template → fill README → write/adapt the deploy runbook → deploy → register in
  [`docs/services/`](../services/README.md) inventory and Uptime Kuma. A service missing any of
  these is not "deployed", it is "being tested".
- **Change:** config changes go through Git when version-controlled, and are documented in the
  service `docs/` when runtime-generated.
- **Remove:** stop stack → final backup → move directory to `/archive/YYYY-MM-DD-<name>/` with a
  note explaining the retirement → update inventory. Data directories are removed only after the
  retention window in [`docs/backup/`](../backup/README.md).

## Tradeoffs

Per-service boilerplate (README, env template, scripts dir) costs a few minutes per service;
uniformity pays it back on every operation, script and migration afterward.
