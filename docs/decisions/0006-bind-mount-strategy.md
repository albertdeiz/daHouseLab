# ADR-0006: Bind Mount Strategy

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0003, ADR-0004, ADR-0005, ADR-0008, [docs/standards/storage-and-bind-mounts.md](../standards/storage-and-bind-mounts.md) |

## Context

Every service in daHouseLab runs as a Docker container ([ADR-0003](0003-docker-first.md)),
deployed with Compose ([ADR-0004](0004-docker-compose.md)) on a Raspberry Pi 4 with a USB SSD
([ADR-0005](0005-raspberry-pi-platform.md)). Containers are disposable by design; the data they
produce — databases, uploads, documents, photos — is not.

Docker offers three persistence mechanisms: bind mounts (host path mapped into the container),
named volumes (Docker-managed directories under `/var/lib/docker/volumes`), and anonymous
volumes (named volumes without a stable name, created implicitly by `VOLUME` directives).
Volume drivers extend named volumes to remote backends such as NFS.

Two platform requirements dominate the choice:

- Backups run as plain scheduled scripts copying files to `/mnt/backups`, an external disk on a
  different physical disk than the data (see [docs/backup/](../backup/README.md)).
- A migration to a Mini PC is planned. Moving the platform must mean copying directory trees to
  a new host, not exporting Docker-internal state.

## Problem

Where does container persistent state live on the host, and through which Docker persistence
mechanism is it mounted?

## Alternatives considered

### Option A — Bind mounts to explicit host paths

- Summary: every persistent path is a bind mount to `/srv/dahouselab/config/<service>` or
  `/srv/dahouselab/data/<service>`, expressed in compose files as `${CONFIG_ROOT}/<service>` and
  `${DATA_ROOT}/<service>`.
- Pros: data location is transparent and predictable; `rsync`, `tar`, `find` and `du` work
  directly; backups and migrations need zero Docker tooling; state survives
  `docker system prune` and even a full Docker reinstall.
- Cons: host paths and ownership must exist with correct `PUID:PGID` before first start; ties
  containers to a host filesystem layout; forgoes volume-driver features.
- Why chosen: it is the only option where the backup and migration story is "copy these
  directories", which is the platform's core durability requirement.

### Option B — Named Docker volumes

- Summary: declare `volumes:` in compose; Docker manages storage under
  `/var/lib/docker/volumes/<name>/_data`.
- Pros: no pre-created directories; Docker handles permissions on first use; idiomatic Docker.
- Cons: data hides inside `/var/lib/docker`, invisible to naive backup scripts; paths embed the
  Docker root and volume naming scheme, coupling backups to Docker internals; migration requires
  `docker run --volumes-from`-style export dances or copying Docker's data root wholesale;
  a careless `docker volume prune` can destroy data.
- Why not chosen: opacity. Every operational task (backup, restore, inspect, migrate) gains a
  Docker-shaped indirection for no benefit on a single local disk.

### Option C — Anonymous volumes

- Summary: rely on images' `VOLUME` directives; Docker creates unnamed volumes per container.
- Pros: zero configuration.
- Cons: data lifecycle is tied to container lifecycle accidents — `docker compose up
  --force-recreate` or image changes can silently orphan data under a random hash; effectively
  undiscoverable for backups.
- Why not chosen: anonymous volumes are how homelab data gets lost. Rejected outright.

### Option D — Volume drivers (NFS, local-persist)

- Summary: named volumes backed by a driver pointing at NFS exports or pinned local paths.
- Pros: enables network storage; `local-persist` gives named volumes at chosen paths.
- Cons: there is no NAS in this platform — the SSD is local; third-party drivers
  (`local-persist`) are additional unmaintained moving parts on ARM64; NFS adds latency and a
  new failure mode (SQLite over NFS corrupts).
- Why not chosen: solves a problem the platform does not have, at the cost of new dependencies.

## Decision

We will persist all container state exclusively through bind mounts to `/srv/dahouselab` paths,
always expressed via `${CONFIG_ROOT}` and `${DATA_ROOT}` variables — never hardcoded absolute
paths in compose files. Named and anonymous Docker volumes are forbidden; a top-level `volumes:`
key in a compose file fails review. Images that declare `VOLUME` directives get every such path
explicitly bind-mounted so no anonymous volume is ever created. Mechanics are codified in
[storage-and-bind-mounts.md](../standards/storage-and-bind-mounts.md).

## Pros

- Complete transparency: `ls /srv/dahouselab/data` is the authoritative inventory of what exists.
- Backups are `rsync` of two trees to `/mnt/backups` — no Docker commands in the backup path.
- Migration portability: moving to the Mini PC is rsync three trees, adjust `*_ROOT` values,
  `docker compose up` ([migrate-to-mini-pc runbook](../runbooks/migrate-to-mini-pc.md)).
- Data survives any Docker-level destruction, including reinstalling the engine.
- Uniformity: one rule for every service means backup tooling needs no per-service knowledge.

## Cons

- Directory creation and `PUID:PGID` ownership are our responsibility; Docker would otherwise
  create bind-mount sources as `root`, so bootstrap scripts must run before first start.
- Host-path coupling: compose files assume the `/srv/dahouselab` layout exists (mitigated, not
  eliminated, by the `*_ROOT` variables).
- No access to volume-driver features (remote backends, driver-level snapshots).
- Some images misbehave when their `VOLUME` paths are pre-populated bind mounts with unexpected
  ownership; each new service needs a first-start permission check.

## Consequences

- The `/srv/dahouselab/{config,data}/<service>` layout becomes a platform invariant; every
  future service, backup script and runbook may assume it.
- Bootstrap/deploy scripts must create and `chown` service directories — a required, ongoing
  follow-up for every new service.
- [ADR-0008](0008-configuration-data-separation.md) builds directly on this decision by
  splitting the mounted trees into config and data.
- Introducing network storage or a second node later requires superseding this ADR.

## Operational impact

- Adding a service includes a "create and chown directories" step in its deploy procedure.
- Backup scripts operate on `/srv/dahouselab` with plain filesystem tools; restore drills need
  no Docker knowledge until the final `compose up`.
- Disk usage monitoring is `du` over one tree instead of `docker system df`.
- `docker volume ls` returning anything is itself an anomaly worth investigating.

## Security considerations

- Bind mounts expose host paths to containers; a container escape reaches exactly the mounted
  directories, so mounts are scoped per service and never include the repo or system paths
  (rule 5 in [storage-and-bind-mounts.md](../standards/storage-and-bind-mounts.md)).
- Config is mounted `:ro` where the application allows, shrinking what a compromised container
  can tamper with.
- Explicit `PUID:PGID` ownership avoids root-owned data directories, limiting blast radius of
  in-container compromise. No secrets are stored in mount paths themselves.

## Future review

- If a NAS or any network storage joins the platform (volume drivers become relevant).
- If the platform grows beyond one node, where shared storage would force a different model.
- At the Mini PC migration: verify the "rsync three trees" promise held in practice.
- If Docker's bind-mount semantics change materially (e.g. rootless mode adoption altering
  ownership behavior).
