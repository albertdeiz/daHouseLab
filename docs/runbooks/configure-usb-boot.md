# Runbook: Configure USB boot

| Field           | Value           |
| --------------- | --------------- |
| Last reviewed   | 2026-07-14      |
| Estimated time  | 45 minutes      |
| Risk level      | Medium          |
| Automation      | Manual          |

## Purpose

Make the Raspberry Pi 4 boot its operating system from the external USB SSD instead of the SD
card. SD cards die under sustained write load; the SSD is faster and durable
(see [ADR-0005](../decisions/0005-raspberry-pi-platform.md)). When this runbook completes, the
root filesystem runs from the SSD and the old SD card is preserved, untouched, as a rollback path.

## Scope

Covers bootloader EEPROM update, boot-order configuration, flashing the OS to the SSD and
verifying the boot medium. Does **not** cover OS configuration after boot — after switching, run
[bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) against the fresh SSD install (or restore
per [restore-from-backup](restore-from-backup.md)). Does not cover cloning a live SD card to
the SSD — a fresh flash is preferred for reproducibility.

## Prerequisites

- [ ] A Pi currently booting from SD card with SSH access — verify: `ssh <deploy-user>@dahouselab.local hostname`
- [ ] USB SSD attached (USB 3.0 port, powered adequately) — verify on the Pi: `lsblk` shows the SSD (e.g. `sda`)
- [ ] Mac with Raspberry Pi Imager, plus a way to attach the SSD to the Mac for flashing (USB enclosure/cable)
- [ ] `rpi-eeprom` tooling present (default on Raspberry Pi OS) — verify: `rpi-eeprom-update` prints bootloader info

## Risks

- Flashing targets the wrong disk — worst case: wiping the Mac's own drive or the current SD
  card's data. Verify the Imager target device every time.
- A failed/interrupted EEPROM update can leave the board unbootable — rare; recoverable with the
  Raspberry Pi Imager "Bootloader" recovery image on an SD card, but treat power stability seriously.
- Some USB-SATA adapters have UAS quirks that make boot hang — mitigated by the rollback SD card.
- The SD card kept as rollback becomes stale over time — it restores boot, not current state.

## Safety checks

- [ ] Current data is safe: if this Pi already runs services, a fresh backup exists ([execute-backup](execute-backup.md)) — expected: latest backup timestamp is today
- [ ] Stable power: official PSU, no undervoltage — `vcgencmd get_throttled` — expected: `throttled=0x0`
- [ ] The SSD to be flashed contains nothing precious: `lsblk -f` on the Pi — expected: target disk is blank or confirmed expendable
- [ ] You have identified the SSD unambiguously by size/model: `lsblk -o NAME,SIZE,MODEL`

## Procedure

1. **Check the current bootloader version**

   ```bash
   sudo rpi-eeprom-update
   ```

   Expected output shape:

   ```text
   BOOTLOADER: up to date
   CURRENT: <date> (<version>)
   LATEST:  <date> (<version>)
   ```

   If it reports `UPDATE AVAILABLE`, continue to step 2; if up to date, skip to step 3.

2. **Apply the EEPROM update and reboot**

   ```bash
   sudo rpi-eeprom-update -a
   sudo reboot
   ```

   Expected: after reboot, `sudo rpi-eeprom-update` reports `BOOTLOADER: up to date`.
   Do not cut power during the update.

3. **Set the boot order to try SD first, then USB**

   `BOOT_ORDER=0xf41` is read right-to-left: try SD (`1`), then USB (`4`), then restart (`f`).
   SD-first means an inserted SD card always wins — which is exactly the rollback property we want.

   Either interactively:

   ```bash
   sudo raspi-config
   # Advanced Options → Boot Order → B2 (NVMe/USB Boot) → Finish (defer reboot)
   ```

   Or directly in the EEPROM config:

   ```bash
   sudo -E rpi-eeprom-config --edit
   # set: BOOT_ORDER=0xf41   — save and exit; the tool schedules the EEPROM write
   sudo reboot
   ```

   Expected: after reboot, `rpi-eeprom-config` output includes `BOOT_ORDER=0xf41`.

4. **Flash Raspberry Pi OS Lite 64-bit to the SSD**

   Attach the SSD to the Mac. In Raspberry Pi Imager choose *Raspberry Pi OS Lite (64-bit)*,
   select the **SSD** as target, and apply the same OS customisation as in
   [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) step 1 (hostname, user, SSH key,
   key-only auth).

   > **Warning:** this step erases the selected disk. Triple-check the target is the SSD —
   > match its size and model name in the Imager device list.

   Expected: Imager reports "Write successful".

5. **Swap the boot media**

   Power off the Pi, **remove the SD card and store it labeled** ("dahouselab rollback,
   2026-07-14"), attach the SSD to a USB 3.0 port (blue), power on.

   ```bash
   sudo poweroff
   ```

   Expected: the Pi boots from the SSD in under a minute (first boot may take longer while it
   resizes the filesystem).

6. **Confirm the root filesystem is on the SSD**

   SSH in, then:

   ```bash
   findmnt /
   lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
   ```

   Expected: `findmnt /` shows source `/dev/sda2` (a USB disk, not `mmcblk0p2`); `lsblk` shows
   no `mmcblk0` device at all (SD slot empty).

## Verification

- [ ] `findmnt -n -o SOURCE /` returns a `/dev/sd*` device, not `/dev/mmcblk0p2`
- [ ] `vcgencmd bootloader_config | grep BOOT_ORDER` returns `BOOT_ORDER=0xf41`
- [ ] `sudo rpi-eeprom-update` reports the bootloader up to date
- [ ] `sudo reboot` and the Pi comes back from the SSD unaided
- [ ] The old SD card is physically stored and labeled — not reused for anything else
- [ ] Continue with [bootstrap-raspberry-pi](bootstrap-raspberry-pi.md) from step 3 onward to configure the fresh SSD install

## Rollback

At any point: power off, reinsert the labeled SD card, power on. Because `BOOT_ORDER=0xf41`
tries the SD slot first, the old system boots exactly as before — this is why the SD card is
kept untouched. The EEPROM update itself (step 2) is not rolled back; it is
backwards-compatible and does not need to be. If the board will not boot at all after an EEPROM
write, flash the "Bootloader → SD Card Boot" recovery image from Raspberry Pi Imager to a spare
SD card and boot it once (green LED steady = success).

## Troubleshooting

| Symptom                                    | Likely cause                              | Action                                                          |
| ------------------------------------------ | ----------------------------------------- | --------------------------------------------------------------- |
| Black screen, four-blink green LED pattern | No bootable medium found                  | Reseat the SSD on a USB 3.0 port; verify the flash completed     |
| Boot hangs at rainbow/initramfs            | USB adapter UAS incompatibility           | Try another adapter/port; as last resort add `usb-storage.quirks` per adapter ID |
| SSD not detected at boot but works later   | Slow SSD spin-up vs boot timeout          | Set `BOOT_UART=0` aside, add `USB_MSD_STARTUP_DELAY` in EEPROM config, or power SSD externally |
| `rpi-eeprom-update` says update needed forever | Pending update never applied           | Run `sudo rpi-eeprom-update -a` and reboot (do not power-cut)    |
| Pi boots the old system unexpectedly       | SD card left inserted (SD-first order)    | Remove the SD card — by design SD wins when present              |

## Automation opportunities

Steps 1–3 are scriptable as `scripts/enable-usb-boot.sh` (idempotent: check version, apply
update, assert `BOOT_ORDER`). Flashing and physical media swaps are inherently manual.
Verification (`findmnt /` on `sd*`) belongs in [run-health-checks](run-health-checks.md).

## Future improvements

- Evaluate booting from the same SSD that hosts `/srv/dahouselab` vs a separate boot SSD; today
  the layout assumes one SSD for both, sized accordingly.
- Document a tested-good USB-SATA adapter model in `docs/architecture/hardware.md` to kill the
  UAS-quirk troubleshooting class permanently.
