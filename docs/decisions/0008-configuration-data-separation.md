# ADR-0008: Configuration/Data Separation

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0006, ADR-0007, [docs/standards/storage-and-bind-mounts.md](../standards/storage-and-bind-mounts.md) |

## Context

[ADR-0006](0006-bind-mount-strategy.md) fixed *how* container state persists: bind mounts under
`/srv/dahouselab`. It did not fix the internal shape of that state. A service's persistent
footprint is not homogeneous — it mixes at least three kinds of material with different sizes,
change rates and recovery semantics:

| Kind                    | Example                              | Size   | Changes        | Loss means            |
| ----------------------- | ------------------------------------ | ------ | -------------- | --------------------- |
| Runtime configuration   | app settings DB, generated conf      | Small  | Rarely         | Re-setup (annoying)   |
| Application data        | photos, documents, databases         | Large  | Constantly     | Real loss (disaster)  |
| Repo-authored config    | Caddyfile, homepage YAML             | Tiny   | Via Git commit | Nothing — it's in Git |

Many upstream images assume a single `/config`-style directory holding everything, which makes
"wipe the config to fix the app" indistinguishable from "delete the data". Meanwhile
[ADR-0007](0007-git-as-source-of-truth.md) requires repo-authored configuration to live in Git,
which means containers must be able to consume files from the checkout without being able to
write to it.

## Problem

How is a service's persistent state structured on disk so that configuration and data can be
backed up, restored, wiped and reasoned about independently?

## Alternatives considered

### Option A — Separate config and data trees, read-only repo templates

- Summary: per service, runtime config lives in `${CONFIG_ROOT}/<service>` and application data
  in `${DATA_ROOT}/<service>`, mounted as separate bind mounts; config templates authored in the
  repo live in `infrastructure/configs/` and are mounted `:ro`.
- Pros: wiping config never touches data and vice versa; backup policy can differ per tree
  (frequency, retention); disk monitoring separates "big and growing" from "small and precious";
  repo config stays writable only through Git.
- Cons: two mounts minimum per service; some images require path remapping or symlinks to split
  their monolithic `/config`; per-service judgment calls about what counts as which.
- Why chosen: it makes the recovery matrix explicit — every failure mode maps to exactly one
  tree to restore.

### Option B — Single per-service directory

- Summary: one mount, `${DATA_ROOT}/<service>`, holding everything the service persists.
- Pros: one mount, no classification decisions, matches many images' assumptions.
- Cons: "reset the app's config" becomes impossible without touching data; backups cannot
  treat a 2 TB photo library and a 2 MB settings file differently; a misbehaving app rewriting
  its config churns the data tree's backup deltas.
- Why not chosen: it optimizes setup convenience at the cost of every later operation.

### Option C — Configuration baked into images

- Summary: build custom images per service with configuration copied in at build time.
- Pros: truly immutable config; config versioning equals image versioning.
- Cons: every config tweak becomes an image build and re-deploy on a Raspberry Pi; forks
  diverge from upstream images, forfeiting their update stream; runtime-generated config
  (settings the app writes itself) cannot be baked at all.
- Why not chosen: the platform deliberately runs unmodified upstream images
  ([docker-compose-conventions](../standards/docker-compose-conventions.md)); a build pipeline
  is disproportionate for a homelab and doesn't even cover runtime config.

### Option D — Everything under one shared data directory

- Summary: a single flat `/srv/dahouselab` tree where services intermingle files.
- Pros: none beyond zero upfront structure.
- Cons: no ownership boundaries between services; removing a service leaves orphaned files
  nobody can attribute; per-service backup/restore is impossible.
- Why not chosen: baseline anti-pattern, listed to record that "no structure" was considered
  and rejected.

## Decision

We will keep, for every service, runtime configuration and application data in two separate
trees — `${CONFIG_ROOT}/<service>` and `${DATA_ROOT}/<service>` — mounted as separate bind
mounts, never sharing a mount. Configuration authored in the repository (Caddyfile, dashboards,
templates) lives in `infrastructure/configs/` and is mounted read-only from
`${DAHOUSELAB_ROOT}/infrastructure/configs/`; it is the only repo content a container ever sees.
Classification rule: if losing it means re-running setup, it is config; if losing it means
losing user content, it is data; if it is edited via Git commit, it is a repo template.

## Pros

- Independent lifecycles: reset a broken app config without risking data; restore data without
  reviving stale config.
- Differentiated backups: config trees are tiny and can be snapshotted aggressively; data trees
  get the heavyweight schedule ([docs/backup/](../backup/README.md)).
- Repo-authored config is tamper-proof at runtime (`:ro`) and reviewed at change time
  ([ADR-0007](0007-git-as-source-of-truth.md)).
- The three-way split gives every file on the host exactly one authority: Git, config backup,
  or data backup.

## Cons

- More moving parts per service: at least two mounts, sometimes path remapping to fit images
  that expect one directory.
- The config/data boundary is occasionally genuinely ambiguous (e.g. an app's SQLite file that
  holds both settings and user content); each such case needs a documented judgment call.
- Read-only template mounts break applications that insist on writing to their config file at
  runtime; such apps force an exception or a copy-on-start workaround.
- Misclassification is silent until a restore: config wrongly holding data gets the wrong
  backup guarantees.

## Consequences

- Every new service's deployment doc must state what lands in config vs data, decided at review
  time, not discovered later.
- Backup tooling can (and now must) treat `${CONFIG_ROOT}` and `${DATA_ROOT}` as separately
  scheduled sets.
- The `infrastructure/configs/` directory becomes the canonical home for all reviewed,
  version-controlled service configuration — [ADR-0009](0009-caddy-reverse-proxy.md) relies on
  this for the Caddyfile.
- Compose reviews gain a concrete check: at least two mounts, no shared mount, repo mounts `:ro`.

## Operational impact

- "Reset the app" runbooks become safe one-liners: stop, wipe `${CONFIG_ROOT}/<service>`, start.
- Restore drills exercise config-only and data-only restores as distinct procedures.
- Editing repo-authored config is a Git workflow (edit, commit, reload service) — never `vi`
  inside a running container.
- Disk alerts can use different thresholds per tree: growth in config trees is a red flag,
  growth in data trees is normal life.

## Security considerations

- Read-only mounting of repo config removes a persistence avenue: a compromised container
  cannot rewrite its own reviewed routing/config to survive redeploys or widen access.
- Separate trees narrow blast radius — a service compromise exposes its two directories, and
  data shares mounted into other services stay `:ro` unless write access is required
  (rule 4 in [storage-and-bind-mounts.md](../standards/storage-and-bind-mounts.md)).
- Runtime config may contain secrets written by applications; `${CONFIG_ROOT}` therefore gets
  the same handling discipline as `.env` files in backups.

## Future review

- If several services accumulate awkward workarounds to split monolithic `/config` layouts,
  re-evaluate whether the split earns its complexity for those services.
- If a secrets manager is adopted (see [ADR-0007](0007-git-as-source-of-truth.md) future
  review), re-examine which runtime config still needs backup at all.
- At the Mini PC migration: confirm the two-tree restore procedure works end-to-end on new
  hardware before decommissioning the Pi.
