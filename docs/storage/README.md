# Storage Documentation

Where every byte lives, who owns it, and how it survives hardware replacement.

## The storage model

Three concerns are physically separated and never mixed
([ADR-0006](../decisions/0006-bind-mount-strategy.md),
[ADR-0008](../decisions/0008-configuration-data-separation.md)):

| Path                                | Concern                        | Lifecycle                                  |
| ----------------------------------- | ------------------------------ | ------------------------------------------ |
| `/opt/dahouselab`                   | Infrastructure (this repo)     | Reproducible from Git — disposable         |
| `/srv/dahouselab/config/<service>`  | Runtime configuration          | Small, precious — backed up                |
| `/srv/dahouselab/data/<service>`    | Application data               | Large, precious — backed up                |
| `/mnt/backups`                      | Backups (external disk)        | The last line of defense — tested restores |

User-facing shares (media, photos, documents, projects, downloads) live under `DATA_ROOT`
as documented data directories — never inside the repository.

## Scope

- Physical layout: disks, partitions, filesystems, mount points (`/etc/fstab` entries)
- The directory tree under `/srv/dahouselab` and its ownership/permissions model
- Capacity planning and growth expectations per service
- What is intentionally **not** stored (and why)

## Ground rules

- The Git repository never contains real data ([ADR-0007](../decisions/0007-git-as-source-of-truth.md)).
- Anonymous Docker volumes are forbidden; all persistence uses bind mounts to the paths above.
- `BACKUP_ROOT` lives on a different physical disk than `DATA_ROOT`, always.

Conventions: [`../standards/storage-and-bind-mounts.md`](../standards/storage-and-bind-mounts.md).
Related runbooks: [replace-ssd](../runbooks/replace-ssd.md), [configure-usb-boot](../runbooks/configure-usb-boot.md).
