# ADR-0016: memvid as the Personal Knowledge Base — a Batch Job, Not a Service

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-09-21                               |
| Deciders | albertdeiz                               |
| Related  | [ADR-0008](0008-configuration-data-separation.md), [ADR-0003](0003-docker-first.md), [ADR-0005](0005-raspberry-pi-platform.md), [ADR-0015](0015-hermes-agent-self-hosted-ai.md), [build-knowledge-base](../runbooks/build-knowledge-base.md) |

## Context

Personal documents accumulate in [Nextcloud](../../services/nextcloud/README.md) — PDFs, notes,
manuals, references — and are findable only by filename. The wanted capability is to **ask
questions of them** in natural language, from the workstation where work actually happens.

[memvid](https://memvid.com/) v2 provides exactly that, but it is **not a service**. It is a Rust
core with a CLI and SDKs that produces a single self-contained `.mv2` file holding data,
embeddings and indices. There is no daemon, no HTTP API and no documented concurrent-access story.
The v1 QR-in-MP4 design that made it well known is deprecated.

Two facts shape everything below:

- `memvid-cli` publishes a **`@memvid/cli-linux-arm64`** binary, so the Pi can build the file.
- The default embedder is **local BGE** — no API key, no data egress, but CPU-bound on an
  ARM Cortex-A72.

The platform has no pattern for "a thing that runs periodically and produces an artifact" other
than the nightly backup ([dahouselab-backup.service](../../infrastructure/configs/systemd/dahouselab-backup.service)):
a `oneshot` unit, a timer, a script under [`scripts/`](../../scripts/README.md), and a dead-man push
monitor in Uptime Kuma.

## Problem

How do we give a workstation-side assistant semantic access to documents that live on the Pi,
without inventing a service where there is no daemon, and without a second copy of the truth?

## Alternatives considered

### Option A — Scheduled build on the Pi, delivered through Nextcloud (chosen)

- A nightly containerized job reads the Nextcloud data tree read-only, builds `knowledge.mv2`, and
  drops it into a Nextcloud folder so the existing sync carries it to the Mac. The workstation
  queries it with the `memvid` CLI.
- Pros: the source of truth stays on the Pi; **the Pi writes, the Mac reads**, so there is no
  concurrent-write problem on a binary file; delivery reuses a sync that already exists — no new
  ingress, no new port, no new network path; works whether or not the laptop is on.
- Cons: embeddings on a Pi 4 CPU are slow, so the first run is long; and the job must read another
  service's internal storage layout.
- Why chosen: it is the only option that makes the knowledge base a *platform* capability rather
  than a laptop script, at the cost of one nightly batch window.

### Option B — Build on the workstation from the synced copy

- Run memvid on the Mac against the already-synced Nextcloud folder.
- Pros: no homelab change at all; Apple Silicon builds embeddings far faster; zero coupling to
  Nextcloud's internals.
- Cons: it is not a platform capability — it exists only where that laptop is, and dies with it.
  The repository would document nothing.
- Why not chosen: the point of the homelab is that capabilities live on the platform. Worth
  revisiting if the nightly build proves too slow to be useful.

### Option C — A "memvid service" behind Caddy

- Wrap the CLI in a long-running container to look like every other service.
- Pros: uniform with the rest of the portfolio.
- Cons: dishonest. There is no daemon to run; it would be a container sleeping forever so that a
  healthcheck has something to answer, plus an HTTP wrapper nobody upstream supports.
- Why not chosen: shape follows the thing, not the convention. Forcing a batch tool into the
  service mould would make the repository lie about what is running.

### Option D — Wait for Paperless-ngx

- Ingest from Paperless (OCR'd, tagged) instead of raw Nextcloud.
- Pros: a cleaner, curated corpus.
- Cons: Paperless is planned but not deployed; this would block the capability on an unrelated
  deployment.
- Why not chosen: deferred, not rejected — Paperless becomes an additional source later.

## Decision

We will build the knowledge base as a **scheduled batch job**, not a service:

1. **A pinned image**, `dahouselab/memvid:2.0.160`, built from
   [`infrastructure/images/memvid/`](../../infrastructure/images/memvid/) — the same custom-image
   precedent as Caddy. This keeps [ADR-0003](0003-docker-first.md) intact: the CLI runs in a
   container, never installed on the host.
2. **A `oneshot` unit plus timer**, `dahouselab-knowledge.{service,timer}`, at 04:30 — after the
   03:30 backup, never concurrent with it — mirroring the backup's structure including its
   Uptime Kuma dead-man ping.
3. **Read-only access to Nextcloud's data**, mounted `:ro`. The job writes only to
   `${DATA_ROOT}/knowledge`.
4. **Ingest all of Nextcloud**, with two exclusions that make "all" mean what the operator intends:
   Nextcloud's internal directories (`files_versions/`, `files_trashbin/`, `appdata_*/`, `cache/`),
   which would multiply every document by its version history; and non-textual files, via an
   extension allowlist that is a single editable line in the script.
5. **Incremental runs** keyed on path + mtime, so only the first build is expensive.
6. **Delivery through Nextcloud's own sync.** The artifact is copied into a Nextcloud folder and
   registered with `occ files:scan`; the existing desktop client carries it to the Mac.
7. **No MCP server.** Claude Code already has a shell; `memvid ask <file> "<question>"` needs no
   intermediary. A third-party stdio server would be another moving part to install, pin and
   maintain for no capability gain.

## Pros

- A genuine platform capability: the knowledge base is rebuilt whether or not any laptop is awake.
- No new ingress, port, network or exposed surface — delivery rides infrastructure already in place.
- One writer, many readers: the concurrency question that memvid does not answer never arises.
- Fully local embeddings by default: no document content leaves the house, in contrast to
  [ADR-0015](0015-hermes-agent-self-hosted-ai.md).
- The artifact is disposable — losing it costs a rebuild, not data.

## Cons

- **It couples to Nextcloud's internal storage layout.** This is the first container to read
  another service's data directory, and it is the honest cost of Option A. If Nextcloud changes
  where or how it stores files, this job breaks — silently, producing a stale or empty index.
  Mitigation is the exclusion list plus a `--dry-run` that shows exactly what would be ingested.
- **The first run will be slow.** Local BGE embeddings on an ARM CPU over a whole document library
  is measured in hours, not minutes. It runs overnight, `nice`d, after the backup — and it is
  incremental thereafter.
- **The index is only as fresh as last night.** A document added today is not searchable until
  tomorrow. Accepted; a file-watcher would trade this for constant CPU on a Pi.
- The extension allowlist means "all of Nextcloud" is really "all text-bearing files in Nextcloud".
  Stated plainly so nobody later believes their photos are searchable.

## Consequences

- **A new artifact category exists**: `${DATA_ROOT}/knowledge` holds a *derived* product, not user
  data. It is regenerable, so it may be excluded from backups — noted in
  [`docs/backup/`](../backup/README.md).
- **A new top-level concern in the repository**: `infrastructure/images/` for platform-owned image
  builds that are not services, and `scripts/knowledge/` for this job's automation. Both are
  declared in the structure standard.
- **The non-service pattern is now established.** A future scheduled artifact-producer copies this
  shape rather than pretending to be a service.
- The `.mv2` inside Nextcloud is a **synced binary that changes nightly**. It consumes sync
  bandwidth and version history on every client; Nextcloud's own versioning of it is pure waste and
  should be considered for exclusion if it grows.
- Paperless-ngx, when deployed, becomes an additional input to this same job — not a second one.

## Operational impact

- Procedure: [build-knowledge-base](../runbooks/build-knowledge-base.md), which also covers the
  workstation side (`npm install -g memvid-cli@2.0.160`, the same version as the image).
- Monitored by a Kuma **push** monitor with a 26 h interval: a missing ping means the build stopped
  happening, which otherwise fails completely silently.
- The step that breaks this most often is forgetting `occ files:scan` — Nextcloud does not notice
  files written underneath it, so the artifact never reaches any client while everything else looks
  healthy.
- Version bumps follow [update-containers](../runbooks/update-containers.md); the host CLI and the
  image version must be bumped together, since they read the same file format.

## Security considerations

- **Nextcloud's data is mounted read-only.** The job cannot modify or delete user files; its only
  write target is `${DATA_ROOT}/knowledge`.
- **The index is as sensitive as the documents.** `knowledge.mv2` contains the text of everything
  ingested. It inherits `DATA_ROOT` handling and, once in Nextcloud, is subject to that service's
  sharing — it must never be shared with a link.
- **No data egress.** The default BGE embedder is local. Switching to an API embedder would send
  document content to a third party and is therefore a decision that changes this ADR.
- The job runs as a container with no published ports and no network need beyond the image pull.
- It reads every readable file in the Nextcloud tree, so anything sensitive stored there ends up in
  the index. That is the intended behaviour of "all of Nextcloud" and is worth knowing before the
  first run.

## Future review

- **If the nightly build cannot finish in its window**, reconsider Option B, or narrow the corpus to
  a curated folder.
- **When Paperless-ngx is deployed**, add it as a second, higher-quality source (OCR'd, tagged).
- **If memvid ships a real server mode** with safe concurrent access, revisit the one-writer model.
- **If upstream's file format changes incompatibly**, the image and the workstation CLI must move
  together; a mismatch is the likely first symptom.
- **If Nextcloud's storage layout changes** in a major upgrade, this job's assumptions need
  re-verification — it is the coupling this ADR knowingly accepted.
