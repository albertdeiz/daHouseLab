# Scripts

Automation for the platform, grouped by purpose. Scripts are the graduated form of runbooks:
every script here implements (part of) a documented procedure in
[`docs/runbooks/`](../docs/runbooks/README.md) — never an undocumented behavior.

## Contents

| Directory                        | Purpose                                             |
| -------------------------------- | ---------------------------------------------------- |
| [`bootstrap/`](bootstrap/)       | Host preparation: directories, networks, hardening   |
| [`backup/`](backup/)             | Scheduled and on-demand backups                      |
| [`restore/`](restore/)           | Restore procedures                                   |
| [`maintenance/`](maintenance/)   | Updates, cleanup, recurring upkeep                   |
| [`healthcheck/`](healthcheck/)   | Platform verification                                |

## Conventions

- Language: Bash (`#!/usr/bin/env bash`, `set -euo pipefail`) for glue; Python only when Bash
  becomes unreadable.
- Naming: `verb-object.sh` ([naming standard](../docs/standards/repository-structure.md)).
- Every script: a header comment (purpose, usage, linked runbook), idempotent where possible,
  loud on failure (non-zero exit, clear message), and **dry-run support for anything destructive**.
- Configuration via the root `.env` — scripts never hardcode paths or hostnames
  ([environment standard](../docs/standards/environment-variables.md)).
- Scripts log what they do; backup/restore scripts additionally verify what they did.
