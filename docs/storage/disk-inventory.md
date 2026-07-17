# Disk Inventory

Authoritative record of physical storage: what disk is what, by UUID.
Update in the same commit as any `/etc/fstab` change ([bootstrap runbook, step 7](../runbooks/bootstrap-raspberry-pi.md)).

## Disks (host `daHouse`)

| Device (typical) | Medium              | Label               | UUID                                   | Mounted at        | Holds                          |
| ---------------- | ------------------- | ------------------- | -------------------------------------- | ----------------- | ------------------------------ |
| `mmcblk0p2`      | SD card 32 GB       | `rootfs`            | `8abab6b9-ef90-4fee-ae3d-91079bfae7c1` | `/`               | OS **and** `/srv/dahouselab` (see deviation) |
| `sda1`           | USB pendrive 8 GB   | `dahouselab-backup` | `c0dce4c5-4ea0-4d1a-b0a0-b576a2d381b9` | `/mnt/backups`    | Backup sets (`nofail` in fstab) |

Devices names (`sda`…) are incidental — fstab mounts by UUID only.

## Known deviations from the storage standard

- **Data lives on the SD card** (phase 0): `/srv/dahouselab` is on the root filesystem, not on a
  dedicated SSD as [ADR-0005](../decisions/0005-raspberry-pi-platform.md) requires. Accepted
  temporarily; mitigated by the nightly backup to the external disk. Resolution: acquire SSD →
  [configure-usb-boot](../runbooks/configure-usb-boot.md) + [bootstrap steps 5–7](../runbooks/bootstrap-raspberry-pi.md).
- **Backup disk is a small pendrive** (8 GB): sufficient at ~200 MB of data; must be replaced
  by a real disk before Nextcloud/Immich (capacity check is part of their deploy prerequisites).
