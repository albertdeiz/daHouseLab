# Standards — Engineering Handbook

The authoritative conventions for everything in this repository. When any document, compose file
or script conflicts with this handbook, the handbook wins — fix the artifact or change the
standard (via PR + ADR if architectural), never ignore the conflict.

## Why standards

Consistency is more valuable than local perfection. A repository where every service looks the
same can be operated from memory, automated with simple scripts, and safely modified by an AI
assistant. These standards are what make daHouseLab a platform instead of a pile of compose files.

## The handbook

| Standard                                                             | Governs                                              |
| -------------------------------------------------------------------- | ---------------------------------------------------- |
| [`repository-structure.md`](repository-structure.md)                 | Folder layout, folder and file naming                |
| [`markdown-conventions.md`](markdown-conventions.md)                 | Markdown style for all documentation                 |
| [`documentation-conventions.md`](documentation-conventions.md)       | Document types, required sections, linking, tone     |
| [`docker-compose-conventions.md`](docker-compose-conventions.md)     | Compose files, images, networks, labels, healthchecks |
| [`environment-variables.md`](environment-variables.md)               | Environment variable naming and `.env` handling      |
| [`storage-and-bind-mounts.md`](storage-and-bind-mounts.md)           | Host paths, bind mounts, config/data separation      |
| [`service-structure.md`](service-structure.md)                       | Anatomy every service directory must follow          |

## Templates

| Template                                                    | For                          |
| ----------------------------------------------------------- | ---------------------------- |
| [`../decisions/TEMPLATE.md`](../decisions/TEMPLATE.md)      | Architecture Decision Records |
| [`../runbooks/TEMPLATE.md`](../runbooks/TEMPLATE.md)        | Operational runbooks          |
| [`/templates/service/`](../../templates/service/)           | New service scaffolding       |

## Changing a standard

1. Propose the change with its motivation (an ADR if it has architectural consequences).
2. Update the standard document.
3. Migrate existing artifacts to comply, or record an explicit dated exception in the standard.

A standard with silent exceptions is worse than no standard.
