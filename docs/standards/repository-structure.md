# Repository Structure & Naming

## Why

Predictable structure is what allows scripts, humans and AI assistants to navigate the repository
without reading it end-to-end. Consistency beats perfection: an imperfect convention applied
everywhere is more valuable than a perfect one applied sometimes.

## Top-level layout

| Directory          | Purpose                                                    | May contain                          |
| ------------------ | ---------------------------------------------------------- | ------------------------------------ |
| `docs/`            | All documentation                                          | Markdown, Mermaid                    |
| `infrastructure/`  | Platform building blocks shared by all services            | Compose, config templates            |
| `services/`        | One self-contained directory per deployed service          | See [service-structure](service-structure.md) |
| `scripts/`         | Automation, grouped by purpose                             | Shell/Python scripts + READMEs       |
| `templates/`       | Scaffolding for new artifacts                              | Template trees                       |
| `assets/`          | Binary assets referenced by docs                           | Images, exported diagrams            |
| `archive/`         | Retired services and superseded docs (dated)               | Anything, read-only                  |

Nothing lives at the top level except these directories and the root files
(`README.md`, `LICENSE`, `.gitignore`, `.editorconfig`, `.env.example`).

## Naming rules

| Artifact              | Convention                       | Example                          |
| --------------------- | -------------------------------- | -------------------------------- |
| Directories           | `kebab-case`, singular purpose   | `uptime-kuma/`, `ai-prompts/`    |
| Markdown files        | `kebab-case.md`                  | `storage-and-bind-mounts.md`     |
| Directory READMEs     | `README.md` (uppercase)          | —                                |
| ADRs                  | `NNNN-kebab-title.md` (4 digits) | `0003-docker-first.md`           |
| Runbooks              | `verb-object.md`                 | `deploy-nextcloud.md`, `rotate-secrets.md` |
| Compose files         | `compose.yaml`                   | —                                |
| Env templates         | `.env.example`                   | —                                |
| Scripts               | `verb-object.sh` (or `.py`)      | `backup-nextcloud.sh`            |
| Service directories   | Official product name, kebab-case | `paperless-ngx/`, `vaultwarden/` |
| Archived items        | `YYYY-MM-DD-original-name`       | `2026-07-14-system-overview.md`  |

General rules:

- Lowercase everywhere except `README.md`, `LICENSE`, `TEMPLATE.md`.
- No spaces, no underscores in file or directory names (underscores allowed inside scripts' variable names, obviously).
- Names describe **content**, not history (`caddy/`, not `caddy-new/` or `caddy-v2/`).
- Every directory contains a `README.md` stating its purpose. Empty directories that must exist
  in Git carry a `.gitkeep` only when a README would be premature.

## What lives where (decision table)

| You are adding…                       | It goes to…                                   |
| ------------------------------------- | --------------------------------------------- |
| A new deployed application            | `services/<name>/`                            |
| Config shared by multiple services    | `infrastructure/configs/`                     |
| A Docker network definition           | `infrastructure/networks/`                    |
| A one-off or scheduled script         | `scripts/<category>/`                         |
| A decision with alternatives          | `docs/decisions/`                             |
| A human procedure                     | `docs/runbooks/`                              |
| A retired anything                    | `archive/` (dated, with a note why)           |

## Tradeoffs

- Kebab-case filenames diverge from some upstream project styles; uniformity across the repo was
  judged more valuable than fidelity to any upstream convention.
- One-directory-per-service duplicates small amounts of boilerplate; independence and copy-paste
  clarity win over DRY here ([ADR-0004](../decisions/0004-docker-compose.md)).
