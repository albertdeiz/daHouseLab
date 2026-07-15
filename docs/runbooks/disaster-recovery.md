# Runbook: Disaster recovery

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | ~half a day (target RTO)                     |
| Risk level      | High                                         |
| Automation      | Manual — orchestrates `scripts/bootstrap/`, `scripts/restore/` |

## Purpose

Rebuild the entire platform from total loss — house fire scoped to the shelf, theft,
simultaneous board+disk death — assuming only two things survive: **a clone of this Git
repository** (any remote) and **the external backup disk**. This runbook is the reason the
repository exists: every standard (bind mounts under `*_ROOT`, dumps not file copies, pinned
multi-arch images, runbooks for every manual step) was chosen so that this procedure is a
deterministic chain of already-tested runbooks rather than archaeology.

**Assumed RPO:** the last completed backup set (worst case: one backup interval of data lost).
**Target RTO:** ~half a day from replacement hardware in hand to all services verified.

## Scope

Covers: the ordered end-to-end chain from bare replacement hardware to a verified running
platform, and the post-mortem. Does not cover: the detail of each step — each is its own
runbook, linked in order; partial failures (single service, single disk) — use
[restore-from-backup](restore-from-backup.md) or [replace-ssd](replace-ssd.md) directly;
loss of the backup disk itself (that is the gap the off-site copy 3 on the roadmap closes —
until then, repo + no backups recovers infrastructure but not data).

## Prerequisites

- [ ] Replacement hardware: a Pi 4/5 (or x86 Mini PC — then substitute
      [migrate-to-mini-pc](migrate-to-mini-pc.md) host-prep notes), PSU, SSD, SD card for
      initial flash
- [ ] The external backup disk, physically in hand
- [ ] A machine with Git access to the repository remote and Raspberry Pi Imager
- [ ] Credentials that live outside the platform: Tailscale account login, router admin,
      Cloudflare account (DNS + API token re-issue, [ADR-0011](../decisions/0011-dns-01-tls-certificates.md)),
      Namecheap account (registrar), repo remote access, and the `.env` secrets
      (see Risks — this is the known weak point)

## Risks

Worst case here is discovering a circular dependency mid-recovery: e.g. the only copy of
`.env` or the Tailscale login password lived in Vaultwarden, which is down. Mitigations that
must already be true (verify during the yearly exercise, not during the disaster): `.env` is
inside every backup set (it is under the rsync'd trees only if a copy is kept in
`${CONFIG_ROOT}` — otherwise it lives solely in the repo checkout, which is lost; see Future
improvements), and account credentials are exportable from a Vaultwarden client-side cache on
a phone/laptop. Secondary risk: restoring in the wrong order (apps before proxy/DNS) wastes
hours on unreachable-but-healthy services — follow the order exactly.

## Safety checks

Unusual for a runbook: there is nothing to protect except the backup disk — the last copy of
everything.

- [ ] **Mount the backup disk read-only until step 6** on any machine and verify it before
  committing to hardware purchases/paths:

  ```bash
  sudo mount -o ro /dev/sdX1 /mnt/backups
  cat /mnt/backups/dahouselab/latest/MANIFEST.txt
  sha256sum -c /mnt/backups/dahouselab/latest/SHA256SUMS
  ```

  Expected: manifest date = your RPO; all checksums `OK`. Note the date — that is what you are
  recovering *to*.

- [ ] Confirm repo access from any machine: `git ls-remote <repo-remote-url>` lists refs.

## Procedure

Each step delegates to its runbook; this runbook owns only the order and the joins.

1. **Hardware + base OS.** Assemble the replacement host and follow
   [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) end to end — flash, user (UID/GID
   1000), [configure-ssh](configure-ssh.md), [configure-static-ip](configure-static-ip.md)
   (recreate the DHCP reservation for the new MAC), [configure-usb-boot](configure-usb-boot.md),
   and the `/srv/dahouselab` + `/mnt/backups` fstab entries by the *new* disks' UUIDs.

   Expected: hardened host, correct mounts, `id` → uid=1000.

2. **Docker.** Follow [install-docker](install-docker.md).

   Expected: `docker run --rm hello-world` succeeds; compose plugin present.

3. **Repository and secrets.**

   ```bash
   sudo git clone <repo-remote-url> /opt/dahouselab
   sudo chown -R 1000:1000 /opt/dahouselab
   docker network create proxy
   ```

   Recreate `/opt/dahouselab/.env` (mode 600) from the backed-up copy
   (`/mnt/backups/dahouselab/latest/config/` if kept there) or from the out-of-band secrets
   store. If any secret is unrecoverable, rotate it now via the relevant service's mechanism
   and note it for [rotate-secrets](rotate-secrets.md).

   Expected: `test -f /opt/dahouselab/.env && stat -c %a /opt/dahouselab/.env` → `600`.

4. **Remote access first:** [deploy-tailscale](deploy-tailscale.md), re-authing under the
   original node name (delete the lost machine in the admin console). From here the rest can
   be done remotely.

   Expected: `tailscale status` connected, same node name as before the disaster.

5. **Ingress second:** [deploy-caddy](deploy-caddy.md). Caddy's config is in the repo
   (`infrastructure/configs/`), so it needs no restore — it comes up ready to route.

   Expected: Caddy healthy; 502s for everything behind it (nothing restored yet) are normal.

6. **Restore every service from backup, in dependency order.** Remount the backup disk
   read-write (`sudo mount -o remount,rw /mnt/backups`), then run
   [restore-from-backup](restore-from-backup.md) per service — its snapshot-aside step is a
   no-op on an empty host, the rest applies verbatim (rsync config+data, fresh DB containers,
   `pg_restore` dumps, chown, up, verify):

   1. uptime-kuma — monitoring watches the rest of the recovery
   2. homepage
   3. vaultwarden
   4. nextcloud
   5. immich
   6. paperless-ngx

   Expected: after each service, its verification passes before starting the next. Images are
   pulled fresh at their pinned tags — only data was restored.

7. **Full platform health check:** [run-health-checks](run-health-checks.md), complete pass —
   every container healthy, every URL 200, Uptime Kuma green, disk/memory sane.

   Expected: all green. The platform is recovered as of the RPO noted in the safety checks.

8. **Close the loop.**
   - Run [execute-backup](execute-backup.md) — the recovered platform's first backup — and
     [validate-backup](validate-backup.md) against it.
   - Rotate any credential that was exposed or reconstructed under pressure
     ([rotate-secrets](rotate-secrets.md)).
   - Write the post-mortem in [`docs/operations/`](../operations/README.md): what was lost,
     actual RPO/RTO vs targets, every place this runbook deviated from reality — and fix the
     runbooks in the same sitting, per the [runbook rules](README.md).

   Expected: dated post-mortem committed; backup chain re-established.

## Verification

- [ ] All containers `(healthy)`: `docker ps --format '{{.Names}}\t{{.Status}}'`
- [ ] Every inventory URL 200 over HTTPS from a tailnet client
- [ ] Data spot-checks match the RPO date: last file/photo/document before the backup
- [ ] Vaultwarden client syncs successfully against the restored server
- [ ] New backup set written and validated on the recovered platform
- [ ] Actual RTO recorded in the post-mortem

## Rollback

N/A — there is no prior state to roll back to; the pre-disaster state is gone by definition.
Within the procedure, any failed step is retried or its underlying runbook's own rollback is
used. The one irreversible external action is deleting the lost machine from the Tailscale
admin console (step 4), which only matters if the "lost" hardware turns up again — re-auth it
as a new node if so.

## Troubleshooting

| Symptom                                   | Likely cause                                | Action                                                      |
| ----------------------------------------- | ------------------------------------------- | ------------------------------------------------------------ |
| Backup disk unreadable on new host        | Disk damaged in the same event              | Try another machine/adapter; this is the roadmap's off-site-copy argument |
| `.env` nowhere to be found                | Secrets only lived in the lost checkout     | Rotate everything: fresh secrets, service-by-service reconfiguration — slow but recoverable |
| Pinned image tag no longer on registry    | Upstream deleted old tags                   | Use nearest newer tag; verify app migrates the restored data; note in post-mortem |
| Restores fine but URLs dead               | DNS/`${DOMAIN}` records point at old IPs    | Update DNS to the new tailnet IP per network docs           |
| RTO blowing past half a day               | Sequential large rsyncs from one USB disk   | Restore critical services (vaultwarden, nextcloud) first; let media-heavy immich run overnight |
| Tailscale login blocked (2FA device lost) | Identity provider recovery needed           | Provider account-recovery path; keep recovery codes off-platform |

## Automation opportunities

The chain itself should become `scripts/restore/disaster-recovery.sh` orchestrating
`scripts/bootstrap/` (steps 1–3) and `scripts/restore/` (step 6 loop), pausing for the
human-only joins (hardware, Tailscale auth, router). The yearly DR exercise per the
[operating rhythm](../operations/README.md) is the forcing function: each exercise should
convert at least one manual join into script.

## Future improvements

- **Close the `.env` gap:** keep an encrypted copy of `.env` (and Tailscale recovery codes)
  inside every backup set and off-site — verify during every validate-backup run
- Off-site copy 3 (roadmap) — this runbook currently dies with the backup disk
- Print this runbook and store it with the backup disk; the wiki is down during a disaster
- Time a full DR exercise yearly and update the RTO figure above with measured reality
