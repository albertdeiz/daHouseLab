# Storage & Bind Mount Conventions

## Why

Storage is where reproducibility meets reality: containers are disposable, data is not.
This standard makes every byte's location predictable, so backup scripts, migrations and
disaster recovery can treat all services uniformly. Decisions behind it:
[ADR-0006 (Bind Mounts)](../decisions/0006-bind-mount-strategy.md),
[ADR-0008 (Config/Data Separation)](../decisions/0008-configuration-data-separation.md).

## Host directory layout

```text
/opt/dahouselab/                  # This repository (git clone) — disposable
/srv/dahouselab/
├── config/<service>/             # Runtime configuration — small, precious
└── data/<service>/               # Application data — large, precious
/mnt/backups/                     # External backup disk — never the same disk as /srv
```

| Root           | Env var        | Contents                         | Backup     | Survives rebuild |
| -------------- | -------------- | --------------------------------- | ---------- | ---------------- |
| `/opt/dahouselab` | `DAHOUSELAB_ROOT` | Repo checkout                 | Via Git    | Recloned         |
| `…/config/<service>` | `CONFIG_ROOT` | Generated/runtime config     | Yes        | Yes              |
| `…/data/<service>`   | `DATA_ROOT`   | Databases, uploads, documents | Yes       | Yes              |
| `/mnt/backups` | `BACKUP_ROOT`  | Backup sets                       | Is the backup | Independent   |

User-facing shares (`media`, `photos`, `documents`, `projects`, `downloads`) are data:
they live under `${DATA_ROOT}/shares/<name>` and are mounted into whichever services need them.

## Bind mount rules

1. **Bind mounts only.** Named and anonymous Docker volumes are forbidden — data hidden inside
   `/var/lib/docker` is invisible to backups and migrations.
2. **Always via variables.** `${CONFIG_ROOT}/<service>:…` and `${DATA_ROOT}/<service>:…` —
   never hardcoded absolute paths in compose files (hardware independence).
3. **Config and data never share a mount.** A service gets at minimum two mounts; wiping config
   must be possible without touching data, and vice versa.
4. **Read-only where possible.** Mount config `:ro` when the application allows it; shared data
   consumed by a service (e.g. media into a viewer) is mounted `:ro` unless it must write.
5. **The container never sees the repo.** Exception: infrastructure services whose config *is*
   version-controlled (e.g. Caddy's Caddyfile) mount that single file/directory `:ro` from
   `${DAHOUSELAB_ROOT}/infrastructure/configs/`.
6. **Ownership is explicit.** Directories are created by the bootstrap/deploy scripts with
   `PUID:PGID` ownership before first start — never left for Docker to create as `root`.

## Filesystem expectations

- `DATA_ROOT` lives on SSD (never on the SD card — [ADR-0005](../decisions/0005-raspberry-pi-platform.md)).
- Filesystem: ext4 (boring, recoverable everywhere). Changing this requires an ADR.
- Mounts are declared in `/etc/fstab` by UUID, documented in [`docs/storage/`](../storage/README.md).

## Tradeoffs

- Bind mounts tie containers to host paths — mitigated by routing every path through the
  `*_ROOT` variables, so a migration is: change three variables, rsync three trees.
- ext4 forgoes snapshots/checksums (ZFS/Btrfs) — accepted for simplicity on Pi-class hardware;
  revisit at the Mini PC migration ([roadmap](../roadmap/README.md)).
