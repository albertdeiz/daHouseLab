# daHouseLab

> Personal homelab platform, built as Infrastructure as Code.

**daHouseLab** is the single source of truth for my self-hosted infrastructure. It currently targets a
Raspberry Pi 4 running Raspberry Pi OS Lite, but the architecture is hardware-independent by design:
the same repository must be able to rebuild the entire platform on a Mini PC — or any Linux host —
with minimal effort.

This is not a collection of Docker Compose files. It is an engineering project: every service is
documented, every decision is recorded, every manual procedure has a runbook, and the complete
infrastructure can be rebuilt from scratch using only this repository.

---

## Mission

Build a production-quality homelab that is:

| Property              | Meaning                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| Self-hosted           | All services run on hardware I own                                       |
| Infrastructure as Code | Everything reproducible from Git — no snowflake configuration           |
| Docker-first          | Applications run in containers, never directly on the host              |
| Documented            | Documentation is a first-class deliverable, more important than code    |
| Hardware-independent  | Migration to new hardware is a documented, low-risk procedure           |
| Secure by default     | No secrets in Git, least privilege, encrypted remote access             |
| Maintainable          | Every decision must still make sense five years from now                |

## Engineering Principles

1. **Simplicity** — the boring solution beats the clever one.
2. **Reproducibility** — if it can't be rebuilt from this repo, it doesn't exist.
3. **Documentation** — answer *why* before *how*. Nothing exists without documentation.
4. **Maintainability** — optimize for the engineer reading this in five years.
5. **Automation** — every recurring manual task is a bug; runbooks graduate into scripts.
6. **Security** — secrets never touch Git; data never touches Git.
7. **Scalability** — infrastructure first, services second.

## Repository Structure

```text
daHouseLab/
├── docs/                  # All documentation (the most important directory)
│   ├── architecture/      # System architecture and diagrams
│   ├── decisions/         # Architecture Decision Records (ADRs)
│   ├── runbooks/          # Step-by-step operational procedures
│   ├── standards/         # Engineering handbook: conventions and templates
│   ├── services/          # Cross-cutting service documentation
│   ├── network/           # Network topology, DNS, reverse proxy
│   ├── storage/           # Storage layout, mounts, filesystems
│   ├── security/          # Security model, secrets handling, hardening
│   ├── backup/            # Backup strategy and retention policies
│   ├── operations/        # Day-2 operations, maintenance, monitoring
│   ├── roadmap/           # Where the platform is going
│   └── ai-prompts/        # Context documents for AI-assisted operations
├── infrastructure/        # Platform-level building blocks (shared by all services)
│   ├── compose/           # Base/shared compose definitions
│   ├── configs/           # Version-controlled configuration templates
│   ├── networks/          # Docker network definitions
│   └── environment/       # Global environment templates
├── services/              # One directory per deployed service (self-contained)
├── scripts/               # Automation (bootstrap, backup, restore, maintenance, healthcheck)
├── templates/             # Scaffolding templates (e.g. new service skeleton)
├── assets/                # Images and diagrams referenced by documentation
└── archive/               # Retired services and superseded documentation
```

Every directory contains a `README.md` explaining its purpose. Start with
[`docs/README.md`](docs/README.md) for the documentation map and
[`docs/standards/README.md`](docs/standards/README.md) for the engineering handbook.

## Platform Stack

| Layer          | Technology                | Decision record                                                        |
| -------------- | ------------------------- | ----------------------------------------------------------------------- |
| Hardware       | Raspberry Pi 4 (8 GB)     | [ADR-0005](docs/decisions/0005-raspberry-pi-platform.md)                |
| OS             | Raspberry Pi OS Lite (64-bit) | [ADR-0005](docs/decisions/0005-raspberry-pi-platform.md)            |
| Runtime        | Docker + Docker Compose   | [ADR-0003](docs/decisions/0003-docker-first.md), [ADR-0004](docs/decisions/0004-docker-compose.md) |
| Reverse proxy  | Caddy                     | [ADR-0009](docs/decisions/0009-caddy-reverse-proxy.md)                  |
| Remote access  | Tailscale                 | [ADR-0010](docs/decisions/0010-tailscale-remote-access.md)              |
| TLS            | Let's Encrypt via DNS-01 (Cloudflare DNS) | [ADR-0011](docs/decisions/0011-dns-01-tls-certificates.md) |
| Storage        | Bind mounts, config/data separation | [ADR-0006](docs/decisions/0006-bind-mount-strategy.md), [ADR-0008](docs/decisions/0008-configuration-data-separation.md) |

### Services

| Service     | Purpose                        |
| ----------- | ------------------------------ |
| Caddy       | Reverse proxy and TLS          |
| Homepage    | Dashboard / landing page       |
| Nextcloud   | Files, calendar, contacts      |
| Immich      | Photo management               |
| Vaultwarden | Password manager               |
| Paperless-ngx | Document management          |
| Tailscale   | Secure remote access (VPN)     |
| Uptime Kuma | Uptime monitoring and alerts   |

## Host Layout

The repository never contains real data. On the host, three concerns are physically separated:

| Path                          | Purpose                                  | In Git? | Backed up? |
| ----------------------------- | ---------------------------------------- | ------- | ---------- |
| `/opt/dahouselab`             | This repository (code, config templates) | Yes     | Via Git    |
| `/srv/dahouselab/config/<service>` | Runtime configuration per service   | No      | Yes        |
| `/srv/dahouselab/data/<service>`   | Application data per service        | No      | Yes        |
| `/mnt/backups`                | External backup storage                  | No      | Is the backup |

See [`docs/standards/storage-and-bind-mounts.md`](docs/standards/storage-and-bind-mounts.md).

## Getting Started

To rebuild the platform from scratch:

1. Read [`docs/architecture/overview.md`](docs/architecture/overview.md).
2. Follow [`docs/runbooks/bootstrap-raspberry-pi.md`](docs/runbooks/bootstrap-raspberry-pi.md).
3. Deploy services in the order defined in [`docs/runbooks/README.md`](docs/runbooks/README.md).
4. Verify with [`docs/runbooks/run-health-checks.md`](docs/runbooks/run-health-checks.md).

## Contributing (Future Self Included)

- New architectural decision? Write an [ADR](docs/decisions/README.md) first.
- New manual procedure? Write a [runbook](docs/runbooks/README.md) first.
- New service? Copy [`templates/service/`](templates/service/) and follow the checklist in its README.
- In doubt about a convention? The [standards](docs/standards/README.md) directory is authoritative.

## License

[MIT](LICENSE)
