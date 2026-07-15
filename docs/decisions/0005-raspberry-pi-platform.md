# ADR-0005: Raspberry Pi as Initial Platform

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0002, ADR-0003, ADR-0004, [hardware strategy](../architecture/hardware.md) |

## Context

The platform needs its first physical host. The workload is roughly ten containerized services
([ADR-0003](0003-docker-first.md), [ADR-0004](0004-docker-compose.md)) — file sync, photo
management, password vault, document archive, dashboard, monitoring — serving a handful of users
over LAN and Tailscale. The machine runs 24/7 in a home: power draw, noise and heat are real
constraints, and there is no server room.

A Raspberry Pi 4 (8 GB) is already owned. Budget for new hardware exists but is better spent
once the platform's actual resource profile is known rather than guessed. Critically,
[ADR-0002](0002-infrastructure-as-code.md) makes the platform reproducible from this repo, which
means the *first* hardware choice is not a *permanent* hardware choice — provided the
architecture never couples itself to the board.

## Problem

Which hardware and operating system host the platform initially, and what constraints must the
architecture accept — and refuse to accept — as a result?

## Alternatives considered

### Option A — Mini PC now (Intel N100-class)

- Summary: buy a small x86 mini PC (16–32 GB RAM, NVMe) as the first host.
- Pros:
  - amd64 removes the multi-arch image constraint entirely; NVMe I/O; headroom for years.
  - Comparable idle power (~6–10 W) to a Pi with SSD; still silent and small.
- Cons:
  - Up-front cost (~150–300 EUR) spent before the workload's real requirements are measured.
  - The owned Pi 4 sits idle — sunk hardware unused.
  - Buying under uncertainty risks the wrong size in either direction.
- Why not chosen: it is the *destination*, not the starting point. Starting on the Pi costs
  nothing today and turns the eventual purchase into an informed one. Migration is planned, not
  hypothetical.

### Option B — Repurposed old laptop or desktop

- Summary: use existing retired x86 hardware as the host.
- Pros:
  - Free; amd64; a laptop even has a built-in UPS (battery).
- Cons:
  - Aged consumer hardware 24/7 is a reliability lottery (fans, thermal paste, swollen
    batteries); desktop idle draw (40–80 W) is a real yearly cost.
  - No suitable machine currently available in usable condition.
- Why not chosen: nothing appropriate on hand, and the failure and power profile is worse than
  both the Pi and a new Mini PC.

### Option C — NAS appliance (Synology/QNAP)

- Summary: buy a consumer NAS and use its built-in Docker support for the services.
- Pros:
  - Excellent storage story out of the box: RAID, disk management, mature backup apps.
  - Low-effort path for the file/photo workload specifically.
- Cons:
  - Vendor OS on top: constrained Docker, vendor-scheduled updates, web-UI-first administration —
    hostile to the repo-driven model of [ADR-0002](0002-infrastructure-as-code.md).
  - Expensive (400+ EUR diskless) with weak CPUs at the affordable tier.
  - Locks the platform to a vendor ecosystem, the opposite of hardware independence.
- Why not chosen: a NAS is a good *peripheral* for a future platform, but as *the* platform it
  trades away the control this project exists to have.

### Option D — Cloud VPS

- Summary: rent a VPS (Hetzner-class, ~5–10 EUR/month) instead of running hardware at home.
- Pros:
  - Professional power, network and hardware reliability; no home footprint; snapshots.
  - Same Docker/Compose stack would run unchanged.
- Cons:
  - Recurring cost forever, and disk beyond ~80 GB gets expensive — photos and file sync make
    this the dominant cost quickly.
  - Personal data (passwords, documents, photos) resides on rented, provider-accessible
    infrastructure; media access from the LAN pays WAN latency and bandwidth.
  - It isn't a homelab: the physical-layer learning disappears.
- Why not chosen: cost scales with exactly the data this platform is for, and data custody
  off-site defeats a core goal.

## Decision

We will run the platform on the **existing Raspberry Pi 4 (8 GB)**:

- OS: **Raspberry Pi OS Lite, 64-bit** (Debian-based, headless) — 64-bit is mandatory for ARM64
  images and >4 GB RAM use.
- Storage: **USB SSD** for the OS, `/srv/dahouselab` (config and data) and general I/O; **an SD
  card is not used for data** — SD endurance and corruption behavior are unacceptable for
  anything that must persist. Backups go to a separate external disk at `/mnt/backups`.
- We accept single-node operation and the ARM64 constraint **now**, but the architecture must
  remain hardware-independent: **multi-arch images are mandatory** (every service must run on
  arm64 *and* amd64), and no repo file may encode Pi-specific behavior outside the bootstrap
  runbooks.
- A migration to a Mini PC is planned and treated as a first-class, runbook-driven event
  ([migrate-to-mini-pc](../runbooks/migrate-to-mini-pc.md)), not a rescue.

## Pros

- Zero hardware cost today; the platform starts immediately on owned equipment.
- ~4–7 W idle, silent, tiny — ideal residency profile for a home.
- 8 GB RAM is genuinely sufficient for the planned service set at this user count.
- The ARM64 + low-power constraint enforces discipline early: lean services, pinned multi-arch
  images, honest resource budgets — all of which transfer to any future host.

## Cons

- ARM64 excludes or complicates some services (amd64-only images); every candidate service needs
  an architecture check first.
- Modest CPU: heavy workloads (Immich machine-learning jobs, large Nextcloud syncs, transcodes)
  will be slow or must be disabled.
- USB-attached SSD is a reliability and throughput bottleneck compared to NVMe; USB controller
  quirks are a known Pi failure category.
- Single node, no redundancy: any hardware fault takes the whole platform down until rebuild.
- Known migration ahead: some work will be done twice (bootstrap, burn-in) by design.

## Consequences

- "Maintained multi-arch image available?" becomes a hard gate in every service-selection
  decision from now on.
- Resource ceilings shape service configuration (worker counts, cache sizes) and those tunings
  must be documented as Pi-specific where they are.
- The mitigation for single-node fragility is recoverability, not availability: rebuild runbooks
  and backups ([ADR-0002](0002-infrastructure-as-code.md)) carry the durability burden.
- The Mini PC migration runbook must exist and stay current *before* it is needed; this ADR will
  be superseded by a new platform ADR at migration.

## Operational impact

- SSD health (SMART where the USB bridge exposes it) and disk fill levels join routine
  monitoring; thermals are checked seasonally.
- Backups to `/mnt/backups` are non-negotiable and restore-tested — they are the availability
  story.
- Performance complaints are triaged against known Pi ceilings before any config chase.
- Power loss handling (no UPS initially) means filesystem checks after outages are a documented
  procedure.

## Security considerations

- Physical access to the device is trivial in a home and the SSD is unencrypted initially:
  anyone with the disk has the data. Full-disk encryption on ARM has boot/unlock friction;
  documented as an accepted risk, revisit at migration.
- Attack surface is minimized by the platform shape, not the hardware: no router
  port-forwarding, remote access only via Tailscale, only Caddy publishes ports
  ([ADR-0010](0010-tailscale-remote-access.md), [ADR-0009](0009-caddy-reverse-proxy.md)).
- Raspberry Pi OS security updates are the host patch surface; unattended-upgrades for the base
  OS is part of bootstrap.

## Future review

- **Trigger for migration (supersedes this ADR):** sustained RAM/CPU saturation, a required
  service blocked by ARM64, storage outgrowing the SSD, or the first hardware fault — whichever
  comes first.
- If USB storage errors appear in logs even once, re-examine the storage attachment before data
  loss, not after.
- If the household user count grows beyond family scale, re-run the platform sizing decision
  entirely rather than incrementally upgrading.
