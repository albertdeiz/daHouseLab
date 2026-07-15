# Runbook: Update containers

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 20–45 minutes per service                    |
| Risk level      | Medium                                       |
| Automation      | Manual — target home: `scripts/maintenance/` |

## Purpose

Move one service to a newer pinned image version, deliberately: changelog read, backup taken,
tag bumped in Git, rolled out, watched, verified — with a working rollback path or the explicit
knowledge that there isn't one. Monthly cadence per the
[operating rhythm](../operations/README.md). On success the service runs the new version, the
pin change is a reviewed commit, and the old version is still restorable.

## Scope

Covers: updating the pinned image tag(s) of **one service stack per session** — never more
(per the [operations ground rules](../operations/README.md)); includes sidecars (postgres,
redis) within that stack, though DB major-version bumps deserve their own session. Does not
cover: OS package updates (weekly, via [run-health-checks](run-health-checks.md) findings),
adding services, or emergency same-day CVE responses — those follow this runbook compressed,
but never skip the backup.

## Prerequisites

- [ ] It has been a healthy week: latest [run-health-checks](run-health-checks.md) passed
- [ ] The target service chosen and its current pin known:

  ```bash
  grep 'image:' /opt/dahouselab/services/<svc>/compose.yaml
  ```

- [ ] Upstream release notes located (GitHub releases page for the image's project)
- [ ] Clean repo state: `git -C /opt/dahouselab status` — no uncommitted changes
- [ ] Time to watch the service afterwards — never update and walk away

## Risks

Worst case: the new version runs a **database migration on startup, then breaks** — now the
data no longer matches the old version, and reverting the tag alone produces a corrupt or
refusing-to-start service. Rollback then requires the pre-update backup. This is *why* the
backup step is unconditional and why the changelog is read *before*, not after: migrations,
breaking config changes, and renamed env vars are all called out in release notes. Secondary
risk: updating multiple services at once makes any breakage unattributable — hence one per
session.

## Safety checks

- [ ] **Read the changelog** for every version between the current pin and the target. Answer
  in writing (the commit message is a fine place): Does it migrate the database? Any breaking
  config/env changes? Is the target tag multi-arch (ARM64 today, amd64 for
  [migrate-to-mini-pc](migrate-to-mini-pc.md))?

  ```bash
  docker manifest inspect <image>:<new-tag> | grep -E '"architecture"' | sort | uniq -c
  ```

  Expected: both `arm64` and `amd64` present. **If a DB migration is involved, note that
  rollback-by-tag will be impossible — the backup becomes the only rollback.**

- [ ] **Backup the service first** — [execute-backup](execute-backup.md), scope-limited to this
  service: its DB dump step plus rsync of just `${CONFIG_ROOT}/<svc>` and `${DATA_ROOT}/<svc>`
  into the current dated set. Verify:

  ```bash
  set -a; source /opt/dahouselab/.env; set +a
  sudo ls -lht "${BACKUP_ROOT}"/dahouselab/daily/$(date +%F)/data/<svc>/db-dumps/ | head -n 3
  ```

  Expected: a dump from the last hour. No fresh backup → do not update.

- [ ] Service currently healthy: `docker compose --project-directory /opt/dahouselab/services/<svc> ps`
  — updating an already-broken service is [restore-from-backup](restore-from-backup.md)'s job,
  or debugging, not this runbook.

## Procedure

1. **Bump the pinned tag in `compose.yaml` via a Git commit.** Edit the `image:` line(s) —
   pin to the exact new version, never `:latest` (per
   [compose conventions](../standards/docker-compose-conventions.md)) — and record the date
   and changelog verdict:

   ```bash
   cd /opt/dahouselab/services/<svc>
   $EDITOR compose.yaml
   git add compose.yaml
   git commit -m "update(<svc>): 1.32.0 -> 1.33.1

   Changelog reviewed: no breaking changes; DB migration: yes (rollback = backup only).
   Pinned 2026-07-14."
   ```

   Expected: one clean commit containing only the tag change(s). This commit is the rollback
   handle.

2. **Pull and roll out:**

   ```bash
   docker compose pull
   docker compose up -d
   ```

   Expected: new image(s) pulled at the pinned tag; containers recreated. `up -d` only
   recreates containers whose config changed — sidecars with untouched tags are left alone.

3. **Watch it come up** — health and logs until steady state, especially any migration:

   ```bash
   docker compose ps
   docker compose logs -f --tail=200
   ```

   Expected: healthcheck reaches `(healthy)`; logs show a clean start (and, if applicable, a
   *completed* migration — do not interrupt a migration in progress, even a slow one).

4. **Verify the application** — the Verification section of the service's deploy runbook
   (e.g. [deploy-immich](deploy-immich.md)): log in over HTTPS, exercise a core action (open a
   file / upload a photo / view a document), check the version string in the UI or:

   ```bash
   docker compose images
   ```

   Expected: running image matches the new pin; the app works; Uptime Kuma monitor stayed/went
   green.

5. **Confirm platform health** — quick pass of [run-health-checks](run-health-checks.md)
   checks 1 and 5 (containers + URLs), then log the update in the operations log.

   Expected: no collateral damage; dated log entry exists.

## Verification

- [ ] `docker compose ps` — all containers in the stack `(healthy)`
- [ ] App reachable and functional at its `dahouselab.url` (200, real user action tested)
- [ ] `git log -1 --stat` shows exactly the intended pin change, pushed to the remote
- [ ] No error-level lines in `docker compose logs --since 30m`
- [ ] Uptime Kuma monitor green for 30+ minutes post-update

## Rollback

**If the changelog said "no DB migration":** revert and re-up with the old tag —

```bash
cd /opt/dahouselab/services/<svc>
git revert --no-edit HEAD
docker compose pull && docker compose up -d
```

**If a DB migration ran (or you are unsure):** tag revert is NOT sufficient and may be
actively harmful — the old binary meets a new schema. Roll back via
[restore-from-backup](restore-from-backup.md) using the pre-update backup taken in the safety
checks, then `git revert` the pin so compose matches the restored data. This asymmetry is the
entire reason the changelog and backup steps precede the bump.

## Troubleshooting

| Symptom                                       | Likely cause                             | Action                                                      |
| ---------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------ |
| `pull` fails: manifest unknown                 | Typo'd tag / tag not published for arm64 | Check the registry page; pick a published multi-arch tag    |
| Container restart-loops citing config/env      | Breaking config change missed            | Re-read release notes; adjust `.env`/config; or roll back   |
| Migration runs for a very long time            | Big schema change on Pi-class I/O        | Wait — interrupting is worse; check `docker stats` for progress signs |
| Healthy container, app errors in UI            | Cached client / stale sidecar version    | Hard-refresh; check sidecar compatibility matrix (e.g. immich server ↔ ML) |
| Old and new containers both present            | Stale container from manual experiments  | `docker compose up -d --remove-orphans`                     |
| Disk filled during pull                        | Accumulated old images                   | `docker image prune -a` (after confirming rollback no longer needs the old image) |

## Automation opportunities

`scripts/maintenance/update-service.sh <svc> <new-tag>`: enforce clean git state, scoped
backup (calling `scripts/backup/`), tag edit + commit, pull/up, and a watch loop that fails
loudly if health doesn't return within N minutes. What stays human: reading the changelog and
the migration/rollback verdict — the script should demand a `--migration=yes|no` flag so the
human answer is recorded, not skipped. A weekly "new versions available" report (diff pins vs
registries) belongs in `scripts/healthcheck/`.

## Future improvements

- Add a per-service update-notes file capturing quirks discovered (e.g. immich's server/ML
  version coupling, Nextcloud's one-major-at-a-time upgrade rule)
- Renovate-style automated PRs that bump pins (still applied via this runbook)
- Track "pin age" in health checks so stale services surface before they are many majors behind
