# Runbook: Run health checks

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 10 minutes                                   |
| Risk level      | Low                                          |
| Automation      | Manual — target home: `scripts/healthcheck/` |

## Purpose

The weekly (per the [operating rhythm](../operations/README.md)) — and after-any-change —
verification that the whole platform is healthy: containers, disks, memory, backups, URLs,
monitoring, and pending updates. Ten minutes, entirely read-only, ending in either "all green"
or a concrete follow-up task. Also the acceptance gate other runbooks
([restore-from-backup](restore-from-backup.md), [replace-ssd](replace-ssd.md),
[disaster-recovery](disaster-recovery.md)) end with.

## Scope

Covers: observing platform health and recording findings. Does not cover: fixing anything —
each failed check routes to its owning runbook or an operations-log task. No check in this
runbook mutates state (the security-updates check only *lists* packages).

## Prerequisites

- [ ] SSH access to the host
- [ ] Global env loadable: `set -a; source /opt/dahouselab/.env; set +a`
- [ ] A tailnet client for the HTTPS checks (URLs resolve only inside the tailnet)

## Risks

Near zero — everything is read-only. The real risk is *interpretive*: rubber-stamping a
marginal reading (disk at 79%, backup 6 days old) week after week until it becomes an
incident. The healthy ranges below exist so the pass/fail call is mechanical, not a judgment
made at check time.

## Safety checks

N/A — this runbook is itself the safety check; no mutating step exists. Do not "quickly fix"
things mid-checklist; finish the sweep first so the operations-log entry reflects one
consistent snapshot.

## Procedure

Run top to bottom; note every ❌ and finish the list before acting on any of them.

1. **Container health** — every service stack, every container healthy:

   ```bash
   for d in /opt/dahouselab/services/*/; do
     docker compose --project-directory "$d" ps --format '{{.Name}}\t{{.Status}}'
   done
   docker ps -a --filter status=exited --filter status=restarting --format '{{.Names}}\t{{.Status}}'
   ```

   Healthy: every line `Up ... (healthy)`; second command prints nothing. Any `(unhealthy)`,
   `Restarting`, or unexpected `Exited` → inspect `docker compose logs --tail=100 <svc>`.

2. **Disk usage watermarks** — data disk, backup disk, and root:

   ```bash
   df -h /srv/dahouselab /mnt/backups /
   ```

   Healthy: `/srv/dahouselab` < 80% (warning ≥80%, act ≥90%), `/mnt/backups` < 80%, `/` < 70%.
   Crossing a watermark → capacity task per [`docs/operations/`](../operations/README.md)
   (prune, grow, or [replace-ssd](replace-ssd.md)). Also confirm both mounts *exist* — a
   missing `/mnt/backups` line means backups have been failing.

3. **Memory pressure** — 8 GB Pi, all stacks resident:

   ```bash
   free -h
   ```

   Healthy: `available` ≥ 1.5 GiB and swap used < 256 MiB. Chronically low available memory →
   check the top consumers (`docker stats --no-stream`) before adding services.

4. **Backup freshness** — the manifest of the latest set:

   ```bash
   grep -E 'backup_date|created' "${BACKUP_ROOT}/dahouselab/latest/MANIFEST.txt"
   ```

   Healthy: `backup_date` within the backup schedule (≤ 7 days for weekly-or-better; the
   scripted target is daily). Stale → run and debug [execute-backup](execute-backup.md) today,
   not next week.

5. **Every inventory URL responds 200 over HTTPS** (from a tailnet client; the inventory is
   the `dahouselab.url` labels across compose files):

   ```bash
   for url in \
     https://home.${DOMAIN} https://status.${DOMAIN} https://vault.${DOMAIN} \
     https://cloud.${DOMAIN} https://photos.${DOMAIN} https://docs.${DOMAIN}; do
     printf '%-40s %s\n' "${url}" \
       "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "${url}")"
   done
   ```

   Healthy: every line `200` (a login redirect `302` from an app root is acceptable if
   documented — note it, don't shrug at it). Non-200 → Caddy logs first
   (`docker logs caddy --tail=50`), then the app.

6. **Uptime Kuma green** — open `https://status.${DOMAIN}`:

   Healthy: all monitors up, no monitor paused-and-forgotten, and the notification channel has
   delivered a test alert within the last quarter (send one now if unsure — a silent alerting
   path is the same as no alerting).

7. **Pending security updates** — list only; applying them is a maintenance-window task:

   ```bash
   sudo apt-get update -qq
   apt list --upgradable 2>/dev/null | grep -iE 'security|docker' || echo "none flagged"
   apt list --upgradable 2>/dev/null | wc -l
   ```

   Healthy: no security-flagged packages waiting more than a week. Container image updates are
   deliberately *not* checked here — they follow the monthly
   [update-containers](update-containers.md) cadence.

8. **Docker housekeeping** — reclaimable space and restart counters:

   ```bash
   docker system df
   docker ps --format '{{.Names}}' | xargs -r docker inspect \
     --format '{{.Name}}\t{{.RestartCount}}' | awk -F'\t' '$2 > 0'
   ```

   Healthy: reclaimable image space < 5 GB (prune during a maintenance window otherwise);
   second command prints nothing — a nonzero `RestartCount` means a container has been
   silently crash-recovering since its last recreate. Investigate its logs.

9. **Host vitals** (30 seconds, catches slow-burn hardware issues):

   ```bash
   uptime
   vcgencmd measure_temp && vcgencmd get_throttled
   sudo dmesg --level=err,warn --since -7days | tail -n 20
   ```

   Healthy: load sane for 4 cores (< 4.0 sustained), temp < 70°C, `throttled=0x0`, no
   recurring I/O/USB errors in dmesg.

10. **Record the result** — one line in the operations log
   ([`docs/operations/`](../operations/README.md)): date, PASS or the list of ❌ items, each
   with its follow-up task. An unrecorded check didn't happen.

## Verification

Self-verifying — the checklist *is* the verification. Meta-check: the operations log shows an
entry for every week (gaps mean the rhythm is broken — that itself is a finding).

## Rollback

N/A — read-only procedure; nothing to roll back.

## Troubleshooting

| Symptom                                    | Likely cause                            | Action                                                     |
| ------------------------------------------ | --------------------------------------- | ----------------------------------------------------------- |
| A container is `Up` but not `(healthy)`    | Healthcheck missing from compose file   | Add one — mandatory per [compose conventions](../standards/docker-compose-conventions.md) |
| All URLs fail from the client              | Client off the tailnet / DNS            | `tailscale status` on the client; then per-service triage  |
| One URL 502, container healthy             | Caddy ↔ app network membership          | `docker network inspect proxy`; re-`up -d` the service     |
| `latest` manifest missing                  | Backup disk unmounted or backups broken | Mount it; run [execute-backup](execute-backup.md); investigate since-when |
| `get_throttled` ≠ 0x0                      | Power supply / cooling                  | Official PSU, check cabling, add cooling; recheck next week |
| Swap heavily used, available RAM fine      | One-off spike since last reboot         | Note it; `swapoff -a && swapon -a` only in a maintenance window |

## Automation opportunities

This is the most automatable runbook in the repo: `scripts/healthcheck/run-health-checks.sh`
implementing checks 1–5 and 7–9 with the healthy ranges as exit criteria, run by systemd
timer, pushing success to an Uptime Kuma push monitor — so a *failure to check* also alerts.
Check 6 (alert-path test) and the judgment in step 10 stay human. Once scripted, this runbook shrinks
to "run the script; investigate what it flags."

## Future improvements

- Generate the URL list dynamically from `dahouselab.url` labels instead of hardcoding
- Add SMART health (`smartctl -H`) once the tooling is installed — feeds
  [replace-ssd](replace-ssd.md) planning
- Trend disk usage over time (weekly `df` appended to a CSV) to forecast watermark crossings
