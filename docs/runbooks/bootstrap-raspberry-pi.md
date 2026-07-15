# Runbook: Bootstrap Raspberry Pi

| Field           | Value           |
| --------------- | --------------- |
| Last reviewed   | 2026-07-14      |
| Estimated time  | 90 minutes      |
| Risk level      | Medium          |
| Automation      | Manual          |

## Purpose

Take a Raspberry Pi 4 from empty storage to a managed host: OS installed, reachable over SSH by
key, storage tree mounted, security patches automated, and this repository cloned to
`/opt/dahouselab` with a real `.env`. When this runbook completes, the host is ready for
[configure-ssh](configure-ssh.md), [configure-static-ip](configure-static-ip.md) and
[install-docker](install-docker.md).

## Scope

Covers flashing, first boot, base OS configuration, storage layout and repo checkout.
Does **not** cover SSH hardening, static addressing, USB boot ([configure-usb-boot](configure-usb-boot.md)),
Docker, or any service deployment — those are separate runbooks linked at the end.

## Prerequisites

- [ ] Raspberry Pi 4 (8 GB), power supply, boot medium (SD card, or SSD if [configure-usb-boot](configure-usb-boot.md) was already done on this board), external SSD, external backup disk
- [ ] Mac with Raspberry Pi Imager installed — verify: `brew list --cask raspberry-pi-imager` (or install with `brew install --cask raspberry-pi-imager`)
- [ ] An SSH keypair on the Mac — verify: `ls ~/.ssh/id_ed25519.pub` (generate with `ssh-keygen -t ed25519` if missing)
- [ ] Read access to the daHouseLab Git remote — verify: `git ls-remote <REPO_URL>` from the Mac
- [ ] The values you will put in `.env` decided: `TZ`, `DOMAIN`, `HOST_IP` (see [environment-variables](../standards/environment-variables.md))

## Risks

- Flashing writes to the wrong disk on the Mac — worst case: destroying the Mac's own data. Double-check the target device in Imager.
- Formatting the SSD or backup disk erases everything on it — worst case: destroying the only copy of existing data. Only format disks you have verified are blank or expendable.
- A wrong `/etc/fstab` entry without `nofail` can make the Pi unbootable if a disk is absent.

## Safety checks

- [ ] The Imager target is the SD card / SSD, not a Mac disk: in Imager, the device size and name match the inserted medium
- [ ] Before formatting any disk on the Pi, list it and confirm it holds nothing precious: `lsblk -f` — expected: the target disk shows no filesystem, or one you have confirmed is expendable
- [ ] The Mac can resolve the Pi after boot: `ping -c 3 dahouselab.local` — expected: replies (run after step 3)

## Procedure

1. **Flash Raspberry Pi OS Lite 64-bit with preconfiguration**

   Open Raspberry Pi Imager on the Mac. Choose *Raspberry Pi OS Lite (64-bit)* (Bookworm),
   select the boot medium, then in **OS customisation** (gear icon / Cmd+Shift+X) set:

   - Hostname: `dahouselab`
   - Username: your deploy user (this becomes UID 1000 — matches `PUID` in `.env`); set a strong password (used only for `sudo`, never for SSH)
   - Enable SSH → *Allow public-key authentication only*, paste the contents of `~/.ssh/id_ed25519.pub`
   - Set locale/timezone to your values

   Write the image and wait for verification to finish.

   Expected: Imager reports "Write successful".

2. **First boot and SSH in**

   Insert the medium, power the Pi, wait ~2 minutes, then from the Mac:

   ```bash
   ssh <deploy-user>@dahouselab.local
   ```

   Expected: a shell on the Pi without any password prompt (key auth).

3. **Update the OS**

   ```bash
   sudo apt update && sudo apt full-upgrade -y && sudo reboot
   ```

   Expected: packages upgrade cleanly; the Pi is reachable again after reboot.

4. **Set timezone and locale** (skip if set correctly in Imager)

   ```bash
   sudo timedatectl set-timezone America/Santiago   # must match TZ in .env
   sudo raspi-config nonint do_change_locale en_US.UTF-8
   ```

   Expected: `timedatectl` shows the correct timezone; no locale warnings on next login.

5. **Identify the external disks**

   Plug in the SSD and the backup disk, then:

   ```bash
   lsblk -f
   ```

   Expected: both disks visible (e.g. `sda`, `sdb`) with size, filesystem and UUID. Note which is which by size/label.

   > **Warning:** the next step is destructive — it erases the target disk. Only run it on a blank/expendable disk, and only against the device you identified above.

6. **Format the disks (only if blank)**

   ```bash
   sudo mkfs.ext4 -L dahouselab-data /dev/sdX1     # SSD partition
   sudo mkfs.ext4 -L dahouselab-backup /dev/sdY1   # backup disk partition
   ```

   Expected: `mkfs` completes; `lsblk -f` now shows `ext4` and a UUID for each.

7. **Mount the disks via /etc/fstab by UUID**

   Get the UUIDs, create mount points, and append fstab entries (per [storage standard](../standards/storage-and-bind-mounts.md)):

   ```bash
   sudo blkid /dev/sdX1 /dev/sdY1
   sudo mkdir -p /srv/dahouselab /mnt/backups
   echo 'UUID=<SSD-UUID>    /srv/dahouselab ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
   echo 'UUID=<BACKUP-UUID> /mnt/backups    ext4 defaults,noatime,nofail 0 2' | sudo tee -a /etc/fstab
   sudo systemctl daemon-reload && sudo mount -a
   ```

   Expected: no errors from `mount -a`; `findmnt /srv/dahouselab` and `findmnt /mnt/backups` each show the ext4 mount. Document both UUIDs in [`docs/storage/`](../storage/README.md).

8. **Create the storage tree owned by the deploy user**

   ```bash
   sudo install -d -o "$USER" -g "$USER" /srv/dahouselab/config /srv/dahouselab/data
   ```

   Expected: `ls -ld /srv/dahouselab/config /srv/dahouselab/data` shows both owned by the deploy user (UID 1000).

9. **Enable unattended security upgrades**

   ```bash
   sudo apt install -y unattended-upgrades
   printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades
   ```

   Expected: `systemctl status apt-daily-upgrade.timer` shows the timer active; `sudo unattended-upgrade --dry-run` exits without error.

10. **Clone the repository to /opt/dahouselab**

    ```bash
    sudo apt install -y git
    sudo install -d -o "$USER" -g "$USER" /opt/dahouselab
    git clone <REPO_URL> /opt/dahouselab
    ```

    Expected: `git -C /opt/dahouselab status` reports a clean working tree on the default branch.

11. **Create the real .env from the template**

    ```bash
    cp /opt/dahouselab/.env.example /opt/dahouselab/.env
    chmod 600 /opt/dahouselab/.env
    nano /opt/dahouselab/.env
    ```

    Fill in `TZ`, `PUID=1000`, `PGID=1000`, `DOMAIN`, `HOST_IP`, and the `*_ROOT` paths
    (`CONFIG_ROOT=/srv/dahouselab/config`, `DATA_ROOT=/srv/dahouselab/data`, `BACKUP_ROOT=/mnt/backups`).

    Expected: `ls -l /opt/dahouselab/.env` shows `-rw-------` owned by the deploy user.

## Verification

- [ ] `ssh <deploy-user>@dahouselab.local hostname` returns `dahouselab`
- [ ] `id` on the Pi shows `uid=1000` for the deploy user (matches `PUID`/`PGID` in `.env`)
- [ ] `findmnt /srv/dahouselab` and `findmnt /mnt/backups` both show ext4 mounts by UUID
- [ ] `ls -ld /srv/dahouselab/config /srv/dahouselab/data` — both exist, owned by the deploy user
- [ ] `git -C /opt/dahouselab status` — clean tree; `.env` exists with mode 600
- [ ] `sudo reboot`, then all of the above still hold (fstab survives reboot)

## Rollback

Everything up to step 5 is recoverable by reflashing the boot medium — no external data is touched.
Step 6 (formatting) is the point of no return for whatever was on those disks. To undo fstab
changes (step 7), remove the two added lines from `/etc/fstab` and reboot. To undo the repo
checkout and env file, `rm -rf /opt/dahouselab`. Full rollback of the host itself is always:
reflash and start over — the whole point of this runbook is that this is cheap.

## Troubleshooting

| Symptom                                   | Likely cause                              | Action                                                        |
| ----------------------------------------- | ----------------------------------------- | ------------------------------------------------------------- |
| `dahouselab.local` does not resolve       | mDNS not ready or different subnet        | Find the IP in the router's DHCP leases; `ssh <user>@<ip>`     |
| SSH asks for a password                   | Key not injected by Imager                | Reflash with the key pasted correctly in OS customisation      |
| `mount -a` fails                          | Typo in UUID or filesystem type in fstab  | Fix `/etc/fstab` against `blkid` output before rebooting       |
| Pi does not boot after fstab edit         | Missing `nofail` on an absent disk        | Mount the medium on the Mac / another Linux box, fix fstab     |
| Disk UUID changed                         | Disk was reformatted                      | Update `/etc/fstab` and `docs/storage/` with the new UUID      |

## Automation opportunities

Steps 3–11 are scriptable as `scripts/bootstrap.sh` (idempotent: apt, timezone, fstab from a
declared disk manifest, tree creation, clone). Blocked today by the disk-identification step,
which needs human eyes; a labeled-partition convention (`dahouselab-data`, `dahouselab-backup`)
would remove that. Flashing could move to `rpi-imager --cli` with a saved settings file.

## Future improvements

- Declare disk layout in a versioned manifest instead of prose UUID documentation.
- Pre-bake a custom image (pi-gen or cloud-init) so steps 3–9 disappear entirely.
- Add a `make bootstrap-verify` target that runs the Verification section as a script.
