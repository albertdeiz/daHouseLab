# Runbook: Replace Raspberry Pi

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-07-14                                   |
| Estimated time  | 1–3 hours                                    |
| Risk level      | Medium                                       |
| Automation      | Manual                                       |

## Purpose

Swap the Raspberry Pi board for another Pi (dead board, warranty swap, upgrade to a newer Pi)
with zero data migration: the storage moves with the SSD. On success the new board runs the
same OS or a freshly bootstrapped one, mounts the same `/srv/dahouselab`, answers on the same
Tailscale node name and LAN address, and all services are healthy.

## Scope

Covers: same-platform (ARM64 Pi → ARM64 Pi) board swaps, both paths — (A) the same SSD simply
boots on the new board, and (B) fresh-flash + reattach data. Does not cover: changing
architecture ([migrate-to-mini-pc](migrate-to-mini-pc.md)), replacing the disk itself
([replace-ssd](replace-ssd.md)), or total loss of board *and* disk
([disaster-recovery](disaster-recovery.md)).

## Prerequisites

- [ ] Replacement Pi (Pi 4 or later, 64-bit capable), adequate PSU, same or better RAM
- [ ] The SSD from the old Pi, intact
- [ ] Physical access to both boards, and to the router admin UI (DHCP reservation)
- [ ] Tailscale admin console access (`https://login.tailscale.com/admin/machines`)
- [ ] Fresh backup — see safety checks. If the old Pi still runs, take one now

## Risks

Worst case: the SSD is the only copy of the data and gets corrupted by an underpowered new
board or a bad adapter during first boot. Mitigation: backup before touching hardware, and the
backup disk stays disconnected during the swap. Lesser risks: a stale DHCP reservation pointing
at the old MAC (new Pi gets a different IP; Caddy/DNS and port-free access still work over
Tailscale), and duplicate Tailscale nodes if re-auth is done carelessly.

## Safety checks

- [ ] Backup current and verified (skip only if the old Pi is already dead — then your RPO is
  the last backup, acknowledged):

  ```bash
  set -a; source /opt/dahouselab/.env; set +a
  grep backup_date "${BACKUP_ROOT}/dahouselab/latest/MANIFEST.txt"
  ```

  Expected: today's date (run [execute-backup](execute-backup.md) if not).

- [ ] Record identity facts of the old host while it is reachable:

  ```bash
  hostname; ip -br link; tailscale status --self | head -n 1
  ```

  Expected: hostname, old MAC (for the DHCP reservation), Tailscale node name. Note them down.

- [ ] Unplug the backup disk before the swap so no mistake can reach it.

## Procedure

1. **Shut the old Pi down cleanly** (if it still runs):

   ```bash
   for d in /opt/dahouselab/services/*/; do
     docker compose --project-directory "$d" down
   done
   sudo shutdown -h now
   ```

   Expected: clean poweroff — no filesystem to fsck on the new board.

2. **Choose the path.**
   - **Path A — same SSD boots on the new board** (the normal case: Pi OS images are portable
     across Pi 4/5 of the same generation family): move the SSD to the new Pi, done here.
   - **Path B — fresh flash** (new board needs a newer kernel/firmware than the old image, or
     the OS is suspect): follow [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) on a fresh
     medium — including [configure-ssh](configure-ssh.md), [install-docker](install-docker.md),
     and [configure-usb-boot](configure-usb-boot.md) — then attach the old SSD as the data disk
     and add its `/srv/dahouselab` UUID line to `/etc/fstab`. Clone the repo to
     `/opt/dahouselab` and copy `.env` from `${CONFIG_ROOT}` notes or the old disk.

   Expected: either way, the new board is assembled with the SSD attached.

3. **First boot on the new board — verify base health before services:**

   ```bash
   findmnt /srv/dahouselab
   df -h /srv/dahouselab
   free -h
   ```

   Expected: data mounted from the expected UUID; sane memory. If Path A boot fails, run
   `sudo rpi-eeprom-update` thinking: new boards may need the bootloader/firmware from a fresh
   image — fall back to Path B rather than fighting it mid-swap.

4. **Fix the network identity.** The new board has a new MAC, so the DHCP reservation from
   [configure-static-ip](configure-static-ip.md) no longer matches. In the router UI, move the
   reservation for the host's IP to the new MAC (from `ip -br link`), then renew:

   ```bash
   ip -br link
   sudo dhclient -r eth0 && sudo dhclient eth0 || sudo systemctl restart dhcpcd
   ip -br addr show eth0
   ```

   Expected: the host holds its old LAN IP again.

5. **Re-auth Tailscale as the same node name.** Path A keeps the node state and usually just
   reconnects; verify, and re-auth if the admin console shows it disconnected or duplicated:

   ```bash
   sudo tailscale status
   # if needed (Path B always):
   sudo tailscale up --hostname "<old-node-name>" --ssh
   ```

   Expected: the node appears connected under the **same name**. If a duplicate `<name>-1`
   appears, delete the *old, disconnected* machine entry in the admin console and rename —
   dependents (Caddy DNS names on the tailnet, mobile clients) must not need reconfiguration.
   Per [deploy-tailscale](deploy-tailscale.md).

6. **Start all stacks in dependency order** (Path A: images are already on disk; Path B:
   `docker compose up -d` pulls the pinned ARM64 images fresh):

   ```bash
   for svc in caddy homepage uptime-kuma vaultwarden nextcloud immich paperless-ngx; do
     docker compose --project-directory /opt/dahouselab/services/${svc} up -d
   done
   docker ps --format '{{.Names}}\t{{.Status}}'
   ```

   Expected: every container `(healthy)`.

7. **Reconnect the backup disk** and confirm it mounts:

   ```bash
   sudo mount /mnt/backups && findmnt --target /mnt/backups
   ```

   Expected: mounted. Run [execute-backup](execute-backup.md) within a day on the new board.

## Verification

- [ ] `tailscale status` — same node name, connected; reachable from another tailnet device
- [ ] LAN IP unchanged: `ip -br addr show eth0` matches the reservation
- [ ] Full [run-health-checks](run-health-checks.md) pass — every inventory URL 200 over HTTPS
- [ ] Uptime Kuma shows all monitors green (and recorded the swap window)
- [ ] `vcgencmd measure_temp` and `dmesg` clean after 30 minutes under normal load
- [ ] Operations log entry: date, old/new board serials, path taken (A/B)

## Rollback

Path A: put the SSD back in the old board (if it works) — full rollback at any step. Path B:
same, since the old SSD is only ever *read*; if the fresh flash wrote to the old SSD's OS
partitions (e.g. usb-boot re-flash onto the same disk), rollback is instead
[restore-from-backup](restore-from-backup.md) — which is why the backup safety check is not
optional. Tailscale machine deletion in step 5 is reversible only by re-authing again.

## Troubleshooting

| Symptom                                    | Likely cause                             | Action                                                      |
| ------------------------------------------ | ---------------------------------------- | ----------------------------------------------------------- |
| New board won't boot old SSD               | Old image lacks new board's firmware     | Update EEPROM from SD, or take Path B                       |
| Rainbow screen / power icon, USB resets    | Underpowered PSU on the new board        | Official PSU; powered hub for the SSD                       |
| Host got a different LAN IP                | DHCP reservation still bound to old MAC  | Step 4 — update reservation, renew lease                    |
| Tailscale shows node as duplicate          | Re-auth created a second machine         | Delete the old disconnected entry, keep/rename the new one  |
| Containers restart-looping on Path B       | `.env` not copied / repo not at `/opt`   | Restore `.env`; verify `git -C /opt/dahouselab status`      |
| Clock skew, TLS failures on first boot     | No RTC, NTP not synced yet               | `timedatectl` — wait for sync or set NTP servers            |

## Automation opportunities

The stack start/stop loops and post-swap verification belong to `scripts/maintenance/` and
`scripts/healthcheck/` (shared with [replace-ssd](replace-ssd.md) and
[disaster-recovery](disaster-recovery.md)). Path B's host preparation is exactly the
`scripts/bootstrap/` scope — every improvement there shortens this runbook.

## Future improvements

- Keep a tested cold-spare boot medium so Path B starts from minute zero
- Document board serial + EEPROM version in `docs/` at bootstrap time
- Pre-authorized, tagged Tailscale auth key (stored in Vaultwarden) to make step 5 one command
