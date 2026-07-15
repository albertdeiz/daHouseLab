# Runbook: Migrate to Mini PC

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 1 day (copy time dominates)                  |
| Risk level      | High                                         |
| Automation      | Manual                                       |

## Purpose

Move the platform from the Raspberry Pi (ARM64) to a Mini PC (x86_64). This is **the
hardware-independence payoff** the standards were written for: bind mounts under three `*_ROOT`
variables, pinned multi-arch images, dumps instead of DB file copies — so a cross-architecture
migration is "change nothing in the repo, move the data, re-pull the images". On success the
Mini PC runs every service on its own pulled x86_64 images with the Pi's data, and the Pi is
cleanly decommissioned. **Data, not images, migrates** — containers are rebuilt from the
registry for the new architecture.

## Scope

Covers: one-way ARM64 → x86_64 migration of host role, config, data, and databases, cutover,
and Pi decommissioning. Does not cover: same-architecture swaps
([replace-raspberry-pi](replace-raspberry-pi.md)), disk moves ([replace-ssd](replace-ssd.md)),
or running both machines in production simultaneously — the Pi becomes a warm standby during
migration and nothing more.

## Prerequisites

- [ ] Mini PC with a Linux distro supported by Docker (Debian-family keeps the runbooks
      literal), SSD sized ≥ current data, on the LAN
- [ ] **Every image is multi-arch** — verify for each pinned image in every compose file:

  ```bash
  grep -rh 'image:' /opt/dahouselab/services/*/compose.yaml | awk '{print $2}' | sort -u \
    | while read -r img; do
        echo "== ${img}"; docker manifest inspect "${img}" \
          | grep -E '"architecture": "(arm64|amd64)"' | sort | uniq -c
      done
  ```

  Expected: each image lists both `amd64` and `arm64`. Any amd64-less image blocks nothing
  (we are going *to* amd64) but any image lacking `amd64` is a hard blocker — resolve before
  starting (per [docker-compose-conventions](../standards/docker-compose-conventions.md),
  multi-arch was mandatory precisely for this day).
- [ ] Fresh, validated backup: [execute-backup](execute-backup.md) +
      [validate-backup](validate-backup.md), today
- [ ] Same Postgres **major** version pinned in each stack as running on the Pi (dump/restore
      requires it; check `image:` tags for the three postgres containers)
- [ ] Tailscale admin access; router admin access (DHCP/DNS)

## Risks

Worst case: cutover completes, the Pi is wiped, and a service's data proves incomplete — the
migration deadline becomes a restore incident. Mitigations: the Pi is **not** decommissioned
until the Mini PC has run healthy for a week; databases move as dumps (file-copied Postgres
directories are not trusted across kernels/architectures/minor versions); the final rsync
happens with all Pi stacks stopped, so nothing is missed in flight. Split-brain (both machines
serving writes) is prevented by never starting a service on the Mini PC while it still runs on
the Pi.

## Safety checks

- [ ] Backup manifest is from today and checksums pass (see prerequisites)
- [ ] The Mini PC's disk layout matches the [storage standard](../standards/storage-and-bind-mounts.md):

  ```bash
  # on the mini pc
  findmnt /srv/dahouselab && df -h /srv/dahouselab
  ```

  Expected: `/srv/dahouselab` on the internal SSD with free space > Pi's used space.
- [ ] Both machines on the tailnet and reachable: `tailscale ping <other-node>` from each side.

## Procedure

1. **Bootstrap the Mini PC** using [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) as the
   checklist, skipping the Pi-specific steps — Raspberry Pi Imager, EEPROM/
   [configure-usb-boot](configure-usb-boot.md), `raspi-config`, `vcgencmd` checks. Everything
   else applies literally: create the user (UID/GID 1000), [configure-ssh](configure-ssh.md),
   [configure-static-ip](configure-static-ip.md) (a *new* reservation for the Mini PC's MAC),
   [install-docker](install-docker.md), create `/srv/dahouselab/{config,data}` and
   `/mnt/backups` mountpoints.

   Expected: hardened x86_64 host, Docker running, `id` shows uid=1000 gid=1000.

2. **Join the tailnet** with a *temporary* node name (the real name is taken until cutover):

   ```bash
   sudo tailscale up --hostname dahouselab-new --ssh
   ```

   Expected: `dahouselab-new` connected; the rest of the migration can run over the tailnet.

3. **Clone the repo and carry the secrets** (the one file Git does not carry):

   ```bash
   sudo git clone <repo-remote-url> /opt/dahouselab
   sudo chown -R 1000:1000 /opt/dahouselab
   # from the Pi:
   scp /opt/dahouselab/.env dahouselab-new:/opt/dahouselab/.env
   ssh dahouselab-new chmod 600 /opt/dahouselab/.env
   ```

   Expected: repo at `/opt/dahouselab`, `.env` present, mode 600. Create the proxy network per
   `infrastructure/networks/`: `docker network create proxy`.

4. **First rsync while the Pi is live** (bulk copy, hours — production stays up):

   ```bash
   # on the pi
   sudo rsync -aHAX --info=progress2 -e ssh /srv/dahouselab/config/ dahouselab-new:/srv/dahouselab/config/
   sudo rsync -aHAX --info=progress2 -e ssh /srv/dahouselab/data/   dahouselab-new:/srv/dahouselab/data/
   ```

   Expected: exit 0. This pre-seeds the data so the downtime rsync in step 5 is a small delta.
   (Requires root-capable rsync on the receiver; alternatively run the pull from the Mini PC
   with `sudo rsync ... pi:/srv/dahouselab/...`.)

5. **Downtime window: stop the Pi's stacks, dump databases, final delta rsync.**

   > **Warning:** from here until cutover completes, services are down. Do not restart them on
   > the Pi after this point unless executing the rollback.

   ```bash
   # on the pi
   for d in /opt/dahouselab/services/*/; do docker compose --project-directory "$d" down; done
   ```

   Then take fresh dumps exactly as in [execute-backup](execute-backup.md) steps 3–4 (start
   only each `postgres` container for its dump, then down again; SQLite via `sqlite3 .backup`),
   and ship the delta:

   ```bash
   sudo rsync -aHAX --delete -e ssh /srv/dahouselab/config/ dahouselab-new:/srv/dahouselab/config/
   sudo rsync -aHAX --delete -e ssh /srv/dahouselab/data/   dahouselab-new:/srv/dahouselab/data/
   ```

   Expected: quick delta run, exit 0. `--delete` is safe here: the target is the not-yet-live
   Mini PC copy, and the Pi (plus `${BACKUP_ROOT}`) still holds everything.

6. **Restore databases from dumps on the Mini PC** — dumps, not the copied Postgres file
   trees, are the source of truth across architectures. For each of nextcloud, immich,
   paperless-ngx, follow [restore-from-backup](restore-from-backup.md) steps 4–5: move the
   copied `postgres/` directory aside, start the DB container fresh (it pulls the **amd64**
   image), `pg_restore` the dump taken in step 5. Same Postgres major version required.
   SQLite files (vaultwarden, uptime-kuma) are architecture-portable and need no restore —
   the step 5 dumps are their safety net.

   Expected: each `pg_restore` exits 0.

7. **Bring services up in dependency order** — tailscale (already up), caddy, uptime-kuma,
   then the rest. Every `up -d` pulls the pinned tag for amd64:

   ```bash
   # on the mini pc
   for svc in caddy uptime-kuma homepage vaultwarden nextcloud immich paperless-ngx; do
     docker compose --project-directory /opt/dahouselab/services/${svc} pull
     docker compose --project-directory /opt/dahouselab/services/${svc} up -d
   done
   docker ps --format '{{.Names}}\t{{.Status}}'
   ```

   Expected: all `(healthy)`; `docker image inspect --format '{{.Architecture}}' caddy` prints
   `amd64`.

8. **Cut over the identity.** On the Pi: `sudo tailscale logout`. In the Tailscale admin
   console, delete/rename the old machine, then on the Mini PC:

   ```bash
   sudo tailscale up --hostname <old-node-name> --ssh
   ```

   Move the DHCP reservation / any LAN DNS records for the platform IP to the Mini PC's MAC
   (or update `${DOMAIN}` DNS to the Mini PC's tailnet IP, per the network docs).
   Expected: clients reach every URL with zero client-side changes.

9. **Attach the backup disk to the Mini PC**, mount at `/mnt/backups` by UUID in fstab, and
   run a full [execute-backup](execute-backup.md) followed by [run-health-checks](run-health-checks.md).

   Expected: first x86_64 backup set written and verified.

10. **Decommission the Pi (after ≥1 week healthy):** confirm week-long green monitors; wipe
    the Pi's disk (`sudo blkdiscard /dev/sdX` or reformat) **only after** step 9's backup
    validated; remove the Pi's stale DHCP reservation; update `docs/` inventory and write the
    migration entry in the operations log; keep or repurpose the board.

    > **Warning:** wiping the Pi's disk is the point of no return for rollback.

## Verification

- [ ] `uname -m` on the serving host prints `x86_64`; all containers `(healthy)`
- [ ] Every inventory URL returns 200 over HTTPS; Uptime Kuma all green
- [ ] Data spot-checks: newest Nextcloud file, newest Immich photo, newest Paperless document
      all present (created just before the downtime window)
- [ ] `docker image inspect --format '{{.Architecture}}'` on each app image → `amd64`
- [ ] Backup + validation pass on the Mini PC ([validate-backup](validate-backup.md))

## Rollback

Until step 10, the Pi is a complete, stopped copy of production as of the downtime window:
rollback is stop Mini PC stacks → `tailscale logout` on the Mini PC → re-auth the Pi under the
node name → `up -d` the Pi's stacks → move DHCP/DNS back. Data written to the Mini PC after
cutover is lost on rollback — the longer you wait, the more rollback costs. After step 10 there
is no rollback, only [disaster-recovery](disaster-recovery.md) onto whichever hardware exists.

## Troubleshooting

| Symptom                                     | Likely cause                              | Action                                                     |
| ------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------- |
| `no matching manifest for linux/amd64`      | An image is ARM-only after all            | Find an official multi-arch tag; fix compose + ADR note    |
| `pg_restore` errors about locale/collation  | OS locale differs from Pi's               | Recreate DB container with matching `LANG`/`LC_COLLATE`, restore again |
| App boots but data directory looks empty    | rsync trailing-slash mistake              | Compare `du -sb` per service; re-run step 5 delta          |
| Permission denied across the board          | UID/GID ≠ 1000 on the Mini PC user        | Fix user IDs; `chown -R 1000:1000` app trees               |
| Clients still hitting the Pi                | DNS/DHCP cutover incomplete, caches       | Verify step 8; TTLs; `tailscale status` name ownership     |
| Immich ML containers slow/failing           | Model cache built for another arch        | Clear the ML cache dir; models re-download on first run    |

## Automation opportunities

The dump-everything and start/stop-in-order loops are the same code
[execute-backup](execute-backup.md) and [disaster-recovery](disaster-recovery.md) need —
`scripts/backup/` and `scripts/maintenance/` respectively. A `scripts/maintenance/verify-multiarch.sh`
implementing the prerequisite check should run in CI/health checks continuously so the
day-of check is a formality.

## Future improvements

- Rehearse once with a spare x86 box or VM before the real migration
- Revisit ext4-vs-ZFS/Btrfs at this boundary, as flagged in the
  [storage standard](../standards/storage-and-bind-mounts.md)
- Consider keeping the Pi as an off-site replica target (roadmap copy 3)
