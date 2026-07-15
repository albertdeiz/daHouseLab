# Runbook: Replace SSD

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 2–4 hours (dominated by the copy)            |
| Risk level      | High                                         |
| Automation      | Manual                                       |

## Purpose

Replace the SSD holding `/srv/dahouselab` (and possibly the OS) with a new drive — because of
failure warnings, capacity, or preventive rotation — ending with the platform running on the
new SSD, mounted by UUID, all services healthy, and the old SSD intact as a fallback.

## Scope

Covers: copying `/srv/dahouselab` old → new SSD, fstab by new UUID, and the boot-disk case
(delegated to [configure-usb-boot](configure-usb-boot.md)). Does not cover: replacing the
backup disk (repartition + one fresh [execute-backup](execute-backup.md) run suffices), moving
to different hardware ([replace-raspberry-pi](replace-raspberry-pi.md),
[migrate-to-mini-pc](migrate-to-mini-pc.md)), or recovering from an already-dead SSD — that is
[disaster-recovery](disaster-recovery.md).

## Prerequisites

- [ ] New SSD attached (second USB port or USB adapter), visible: `lsblk`
- [ ] Old SSD still readable (if not, stop — use [disaster-recovery](disaster-recovery.md))
- [ ] Physical access to the Pi (USB swaps, possible reboots)
- [ ] A fresh backup exists and validates — see safety checks
- [ ] Know whether the old SSD is also the boot disk: `findmnt /` (source on the SSD → yes)

## Risks

Worst case: mkfs on the wrong device — the live data disk or the backup disk — destroying the
only local copy. Mitigations: a validated backup before anything else; device names verified by
size/serial before formatting; the old SSD is never written to and is kept intact until the new
one has run cleanly for days. A failing source SSD can also die mid-copy — the backup, again,
is the answer.

## Safety checks

- [ ] **Fresh backup first.** Run [execute-backup](execute-backup.md) now, then verify:

  ```bash
  set -a; source /opt/dahouselab/.env; set +a
  grep backup_date "${BACKUP_ROOT}/dahouselab/latest/MANIFEST.txt"
  sudo sha256sum -c "${BACKUP_ROOT}/dahouselab/latest/SHA256SUMS"
  ```

  Expected: today's date, all checksums `OK`. Do not continue without this.

- [ ] Positively identify the new device — size, model, and that it is neither the data nor
  the backup disk:

  ```bash
  lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS
  findmnt -n -o SOURCE --target /srv/dahouselab
  findmnt -n -o SOURCE --target /mnt/backups
  ```

  Expected: the new disk (e.g. `/dev/sdc`) has no mountpoints and is not either source above.
  Write its name down; every destructive command below uses it explicitly.

## Procedure

1. **Stop all stacks** so the source is quiet during the copy:

   ```bash
   for d in /opt/dahouselab/services/*/; do
     docker compose --project-directory "$d" down
   done
   docker ps --format '{{.Names}}'
   ```

   Expected: no application containers running (host-level tailscaled stays up for remote
   access — but do this from console/LAN if the SSD is the boot disk).

2. **Partition and format the new SSD** (ext4 per the
   [storage standard](../standards/storage-and-bind-mounts.md)):

   > **Warning:** destructive to the target device. Triple-check the device name from the
   > safety checks — this erases it irreversibly.

   ```bash
   NEW=/dev/sdX            # the verified new device
   sudo parted -s "${NEW}" mklabel gpt mkpart data ext4 0% 100%
   sudo mkfs.ext4 -L dahouselab-data "${NEW}1"
   ```

   Expected: `lsblk -f "${NEW}"` shows one ext4 partition labeled `dahouselab-data`.

3. **Mount the new partition and copy everything** — `rsync -aHAX` preserves hardlinks, ACLs,
   and xattrs, so the tree arrives identical:

   ```bash
   sudo mkdir -p /mnt/newssd
   sudo mount "${NEW}1" /mnt/newssd
   sudo rsync -aHAX --info=progress2 /srv/dahouselab/ /mnt/newssd/
   ```

   Expected: exit 0. Verify sizes match: `sudo du -sb /srv/dahouselab /mnt/newssd` (small
   deltas from lost+found/metadata are fine; large deltas are not — re-run rsync, it is
   idempotent).

4. **Update `/etc/fstab` to the new UUID.** Get it, then edit the `/srv/dahouselab` line:

   ```bash
   sudo blkid -s UUID -o value "${NEW}1"
   sudoedit /etc/fstab
   # UUID=<new-uuid>  /srv/dahouselab  ext4  defaults,noatime  0  2
   sudo findmnt --verify
   ```

   Expected: `findmnt --verify` reports no errors on the fstab. Keep the old line commented out
   for one line of history, not active.

5. **Boot-disk case only:** if the old SSD also holds the OS (`findmnt /` pointed at it), the
   OS must move too. Follow [configure-usb-boot](configure-usb-boot.md) to flash Raspberry Pi
   OS onto the new SSD's OS partition (or clone the OS partitions with `rpi-clone`/`dd`), then
   re-apply steps 3–4 for the data partition. Data-only SSDs skip this step.

   Expected: per that runbook — the Pi boots from the new SSD.

6. **Swap the disks.** Power down, physically replace old SSD with new in the primary port,
   keep the old SSD safe (do not wipe it), power up:

   ```bash
   sudo shutdown -h now
   # swap hardware, boot
   findmnt /srv/dahouselab
   ```

   Expected: `/srv/dahouselab` mounted from the new partition's UUID.

7. **Verify mounts and the backup disk**, then start all stacks in dependency order:

   ```bash
   findmnt --target /mnt/backups
   for svc in caddy homepage uptime-kuma vaultwarden nextcloud immich paperless-ngx; do
     docker compose --project-directory /opt/dahouselab/services/${svc} up -d
   done
   ```

   Expected: both mounts present; all stacks start. (Tailscale is host-level and needs no
   compose start.)

8. **Run health checks** — the full [run-health-checks](run-health-checks.md) pass.

   Expected: everything green, every inventory URL 200.

## Verification

- [ ] `findmnt -n -o SOURCE,UUID --target /srv/dahouselab` shows the new UUID
- [ ] `docker ps --format '{{.Names}}\t{{.Status}}'` — all `(healthy)`
- [ ] Data spot-checks: open a Nextcloud file, an Immich photo, a Paperless document
- [ ] `sudo dmesg | grep -iE 'i/o error|usb.*reset'` — clean (no new-disk trouble)
- [ ] One [execute-backup](execute-backup.md) run completes against the new disk

## Rollback

Until the old SSD is wiped (which this runbook never does), rollback is: power down, put the
old SSD back, restore the old fstab line, boot. That holds through every step. There is no
point of no return in this procedure as long as the old SSD physically survives — which is why
step 6 says keep it, untouched, for at least a week of healthy operation.

## Troubleshooting

| Symptom                                   | Likely cause                              | Action                                                       |
| ----------------------------------------- | ----------------------------------------- | ------------------------------------------------------------ |
| Pi drops the new SSD under load           | USB power budget exceeded                 | Powered USB hub / official PSU; check `dmesg` for resets     |
| Boot hangs at mount after swap            | fstab UUID typo                           | Boot old SSD (or edit fstab from another machine), fix UUID  |
| rsync slows to a crawl                    | Both disks on the same USB2 bus           | Use the USB3 ports (blue); expect ~100+ MB/s on USB3         |
| Sizes differ a lot after copy             | Copy interrupted / source errors          | Re-run rsync; check `dmesg` on the **old** disk for I/O errors |
| Services up but data missing              | Mounted the wrong partition               | `findmnt`; fix fstab; never write until mounts are right     |
| New disk not visible in `lsblk`           | Adapter/UAS quirk                         | Different adapter/port; `usb-storage.quirks` as last resort  |

## Automation opportunities

Low value to script end-to-end (rare, hardware-bound), but two pieces belong in
`scripts/maintenance/`: a preflight (`verify-disks.sh`: mounts, UUIDs vs fstab, SMART status
via `smartctl -H`) and the ordered stop-all/start-all stack loops, which
[disaster-recovery](disaster-recovery.md) and [migrate-to-mini-pc](migrate-to-mini-pc.md)
also need.

## Future improvements

- Document SMART monitoring so replacement is planned, not reactive (weekly `smartctl` in
  [run-health-checks](run-health-checks.md))
- Keep a pre-formatted spare SSD to cut swap time
- Record disk serials/purchase dates in `docs/storage/`
