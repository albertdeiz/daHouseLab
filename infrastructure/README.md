# Infrastructure

Platform-level building blocks shared by every service. If two or more services depend on it,
it lives here — never inside a single service directory.

**Infrastructure first, services second:** nothing in [`/services`](../services/) may exist
without the pieces here being deployed first.

## Contents

| Directory                        | Purpose                                                        |
| -------------------------------- | --------------------------------------------------------------- |
| [`compose/`](compose/)           | Base and shared Compose definitions (e.g. platform-wide stacks) |
| [`configs/`](configs/)           | Version-controlled configuration templates (e.g. Caddyfile)     |
| [`networks/`](networks/)         | Docker network definitions and creation scripts                 |
| [`environment/`](environment/)   | Global environment templates beyond the root `.env.example`     |

## Rules

- Everything here is a template or definition — runtime state still lives under
  `${CONFIG_ROOT}`/`${DATA_ROOT}` per the [storage standard](../docs/standards/storage-and-bind-mounts.md).
- Changes here affect multiple services: treat every change as platform surgery — read the
  affected service docs, and update [`docs/`](../docs/) in the same commit.
