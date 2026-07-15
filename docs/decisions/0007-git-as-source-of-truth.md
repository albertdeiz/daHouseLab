# ADR-0007: Git as Source of Truth

| Field    | Value                                    |
| -------- | ---------------------------------------- |
| Status   | Accepted                                 |
| Date     | 2026-07-14                               |
| Deciders | albertdeiz                               |
| Related  | ADR-0001, ADR-0002, ADR-0006, ADR-0008, [docs/standards/storage-and-bind-mounts.md](../standards/storage-and-bind-mounts.md) |

## Context

daHouseLab is documentation-first ([ADR-0001](0001-documentation-first.md)) and defined as code
([ADR-0002](0002-infrastructure-as-code.md)): the host is cattle, and everything specific about
the platform must be reproducible from a repository checked out at `/opt/dahouselab`.

That repository coexists on the host with material that must **not** be reproducible from it:
application data under `/srv/dahouselab/data`, runtime configuration under
`/srv/dahouselab/config`, secrets in `.env` files, TLS material Caddy manages, logs, and backup
sets on `/mnt/backups`. Some of this is large (media, photo libraries), some is sensitive
(secrets, certificates, personal documents), and some is churn (logs, caches).

Git is unforgiving about mistakes here: anything committed lives in history forever unless the
history is rewritten, and the repo may be pushed to remotes (which is also its own backup
mechanism). The boundary between "in Git" and "never in Git" therefore has to be an explicit,
enforced decision rather than a habit.

## Problem

What belongs in the Git repository, what is excluded, and how is that boundary enforced?

## Alternatives considered

### Option A — Git for source only, strict exclusion of state

- Summary: the repo holds source code, configuration templates, compose files, scripts and
  documentation. Data, secrets, certs, logs, backups and runtime files are excluded by layout
  (they live outside the checkout) and by `.gitignore`, with review as the second gate.
- Pros: repo stays small, clonable and safely pushable to remotes; a clone plus a data restore
  fully rebuilds the host; secrets never enter history.
- Cons: reproducing the platform needs two artifacts (repo + data/secrets restore); discipline
  is required to keep runtime-generated files from creeping in.
- Why chosen: it is the only boundary that lets the repo be simultaneously public-safe,
  fast to clone, and a complete definition of the platform's *shape*.

### Option B — Everything in Git, including data

- Summary: commit runtime config, secrets (possibly encrypted with git-crypt/SOPS) and even
  application data; one clone restores everything.
- Pros: single-artifact restore; full history of every byte.
- Cons: Git is pathological for large/binary/changing data — a photo library makes the repo
  unclonable; databases change under Git mid-write; secrets in history are a standing breach
  risk even encrypted; every push replicates personal data to whatever remote holds the repo.
- Why not chosen: it conflates two backup problems with opposite requirements. Data durability
  belongs to the backup pipeline ([ADR-0006](0006-bind-mount-strategy.md)), not version control.

### Option C — Wiki/Notion for docs, Git for code only

- Summary: compose files and scripts in Git; documentation in a hosted wiki or Notion.
- Pros: friendlier editing UI; easy sharing.
- Cons: docs drift from the code they describe with no atomic commits across both; not greppable
  or diffable alongside the code; a SaaS dependency for the platform's own memory; violates
  [ADR-0001](0001-documentation-first.md), which makes docs part of the deliverable.
- Why not chosen: documentation must version with the code that it explains. One history.

### Option D — No version control

- Summary: edit files in place on the host; rely on backups of the whole disk.
- Pros: zero tooling overhead.
- Cons: no change history, no review point, no reasoning trail, no safe rollback; "why is it
  like this" becomes unanswerable; a fat-fingered edit is only recoverable from last night's
  backup.
- Why not chosen: incompatible with [ADR-0002](0002-infrastructure-as-code.md); listed only as
  the do-nothing baseline.

## Decision

We will treat the Git repository as the single source of truth for everything that *defines*
the platform, and for nothing that the platform *produces*. In scope: source code,
configuration templates, compose files, scripts, and all documentation. Out of scope, always:
application data, secrets (`.env`, tokens, keys), TLS certificates and keys, logs, backups, and
runtime-generated files (including `compose.override.yaml`). Enforcement is layered: the
filesystem layout keeps state outside the checkout (`/srv/dahouselab`, `/mnt/backups` vs
`/opt/dahouselab`), `.gitignore` blocks known state patterns as a safety net, and review of
every commit is the final gate.

## Pros

- The repo can be pushed to any remote without leaking data or secrets — pushing *is* the
  disaster-recovery copy of the platform definition.
- Full history and diffability for every architectural and configuration change; ADRs, docs and
  code move in the same commits ([ADR-0001](0001-documentation-first.md)).
- Rebuild procedure is deterministic: clone, restore data/secrets from backup, `compose up`.
- Small repo: clones and greps stay fast forever because bulk data can never enter it.

## Cons

- Restoring the platform requires two artifacts: the repo and the data/secrets backup. Losing
  the backup loses data even with a perfect repo.
- Secrets have no versioning at all — a broken `.env` has no history to roll back to; secret
  recovery depends entirely on the backup pipeline.
- `.gitignore` is a blocklist, not a guarantee; a novel file type in a new location can slip
  through, so review vigilance is a permanent tax.
- Runtime config generated by applications ([ADR-0008](0008-configuration-data-separation.md))
  is invisible to Git, so config drift there is only caught by backups, not diffs.

## Consequences

- Every new service must be evaluated at review time for what it writes and where, so its state
  lands outside the repo and its patterns land in `.gitignore` when needed.
- Secrets management becomes a distinct concern with its own lifecycle (creation, backup,
  rotation) documented in [docs/security/](../security/README.md).
- Repo-authored config that containers consume (e.g. the Caddyfile) is deliberately *in* Git and
  mounted read-only — the carve-out formalized in [ADR-0008](0008-configuration-data-separation.md).
- A future secrets tool (SOPS, age, Vaultwarden-backed workflow) would need a new ADR; this one
  fixes only the boundary, not the secrets tooling.

## Operational impact

- All changes flow through commits on `/opt/dahouselab`; ad-hoc edits on the host outside the
  repo are limited to state directories by construction.
- `git status` on the host must be clean after normal operation — dirt indicates something is
  writing into the checkout and must be triaged.
- Backup runbooks cover `/srv/dahouselab` and secrets explicitly, because Git will never carry
  them; restore drills must exercise both artifacts together.

## Security considerations

- The primary risk this ADR mitigates is secret/data leakage via remotes; the layered exclusion
  (layout + `.gitignore` + review) exists because any single layer fails eventually.
- Anything that does slip into history must be treated as compromised: rotate the secret and
  rewrite history — deleting the file in a later commit is not remediation.
- The repo remains safe to host on third-party remotes (GitHub), but remote account compromise
  then exposes the platform's full design; nothing in it may ever assume secrecy of topology as
  a security control (see [docs/security/](../security/README.md)).

## Future review

- If secrets need versioning or sharing (e.g. multiple operators), revisit for encrypted-in-repo
  secrets tooling (SOPS/age) under a new ADR.
- If review repeatedly catches near-misses of the same kind, add pre-commit automation
  (secret scanners, path guards) rather than more vigilance.
- If the repo must become public, re-audit history and the exclusion list before publishing.
