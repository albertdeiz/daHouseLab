# Container Images

Platform-owned image builds that are **not services**.

A service's own image lives in its service directory (see
[`services/caddy/Dockerfile`](../../services/caddy/Dockerfile)). This directory is for images the
platform builds for *tooling* — things invoked by scripts and scheduled jobs, which have no
`compose.yaml` and no long-running container.

| Image                     | Used by                                                                 |
| ------------------------- | ----------------------------------------------------------------------- |
| [`memvid/`](memvid/)      | The nightly knowledge-base build ([ADR-0016](../../docs/decisions/0016-memvid-personal-knowledge-base.md), [build-knowledge-base](../../docs/runbooks/build-knowledge-base.md)) |

## Rules

- **Pin everything**, same as service images — no `:latest`, in the base image or the packages
  installed ([compose conventions](../../docs/standards/docker-compose-conventions.md)).
- Multi-arch only: these must build and run on ARM64 and x86_64
  ([ADR-0005](../../docs/decisions/0005-raspberry-pi-platform.md)).
- Tag as `dahouselab/<name>:<upstream-version>` so the tag states what is inside.
- Building an image here instead of installing a tool on the host is what keeps
  [ADR-0003](../../docs/decisions/0003-docker-first.md) true for automation, not just for services.
