# Runbook: Build the Personal Knowledge Base

| Field           | Value                                        |
| --------------- | -------------------------------------------- |
| Last reviewed   | 2026-09-21                                   |
| Estimated time  | 45 minutes setup; the first build runs for hours unattended |
| Risk level      | Low — reads Nextcloud read-only, writes only to its own directory |
| Automation      | Scripted (`scripts/knowledge/build-knowledge-base.sh`) |

## Purpose

Stand up the nightly job that turns the documents in Nextcloud into a queryable knowledge base.
When complete: `${DATA_ROOT}/knowledge/knowledge.mv2` is rebuilt every night at 04:30, published
into Nextcloud so it syncs to the workstation, monitored by a dead-man push in Uptime Kuma, and
answerable from Claude Code with `memvid ask` ([ADR-0016](../decisions/0016-memvid-personal-knowledge-base.md)).

## Scope

Covers: the pinned memvid image, the build script, the systemd unit and timer, the Nextcloud
delivery path, and the workstation-side CLI.

Does not cover: an MCP server (deliberately omitted — Claude Code has a shell and needs no
intermediary); Paperless-ngx as a source (not deployed yet); an API embedder (would send document
content to a third party, which would change ADR-0016).

## Prerequisites

- [ ] [ADR-0016](../decisions/0016-memvid-personal-knowledge-base.md) read — in particular the
      coupling to Nextcloud's internal layout
- [ ] Nextcloud deployed and healthy, with documents in it
- [ ] The Nextcloud desktop client running on the workstation and syncing
- [ ] Node.js on the workstation (for the reader CLI, step 7)
- [ ] ≥ 2 GB free on `${DATA_ROOT}`: `df -h ${DATA_ROOT}`

## Risks

- **Worst case here is wasted time, not lost data**: the source is mounted read-only and the job
  writes only to `${DATA_ROOT}/knowledge`. The realistic failures are a slow first run, or an index
  that silently never reaches the workstation.
- The first build is CPU-bound for hours. Started at the wrong moment it competes with everything
  else — hence the 04:30 timer, `Nice=10` and idle I/O.
- Ingesting Nextcloud's internal directories would bury each document under its own version
  history. The exclusion list prevents this; step 3 proves it.
- **Everything in the index is readable by whoever holds the file.** If sensitive documents live in
  Nextcloud, they end up in `knowledge.mv2` — which then syncs to every device. Know this before
  the first run.

## Safety checks

- [ ] `df -h ${DATA_ROOT}` → ≥ 2 GB available
- [ ] `free -h` → ≥ 1.5 GiB available (the build is CPU-heavy, not RAM-heavy, but the floor holds)
- [ ] Nextcloud healthy: `docker compose -f /opt/dahouselab/services/nextcloud/compose.yaml ps`
- [ ] The backup timer is not about to fire: `systemctl list-timers dahouselab-backup.timer`

## Procedure

1. **Pull and build the pinned image.**

   ```bash
   cd /opt/dahouselab && git pull
   docker build -t dahouselab/memvid:2.0.160 infrastructure/images/memvid
   docker run --rm dahouselab/memvid:2.0.160 --version
   ```

   Expected: the build succeeds on arm64 and `--version` reports `2.0.160`. The npm package pulls
   `@memvid/cli-linux-arm64` automatically.

2. **Set the delivery target.**

   Edit `scripts/knowledge/build-knowledge-base.sh` and set `KNOWLEDGE_TARGET_USER` to your
   Nextcloud username — the account whose synced folder will receive the index. List the
   candidates:

   ```bash
   source /opt/dahouselab/.env
   ls -1 "${DATA_ROOT}/nextcloud/data" | grep -v appdata_
   ```

   Expected: your username appears. Commit the change — never leave it only on the host.

3. **Dry-run first. This is the step that proves the exclusions work.**

   ```bash
   sudo /opt/dahouselab/scripts/knowledge/build-knowledge-base.sh --dry-run | head -50
   sudo /opt/dahouselab/scripts/knowledge/build-knowledge-base.sh --dry-run \
     | grep -cE "files_versions|files_trashbin|appdata_|/cache/"
   ```

   Expected: a plausible list of your documents, and **`0`** from the second command. A non-zero
   count means the exclusions are not working — fix that before building, or you will index every
   old version of every file.

4. **Run the first build by hand, in a terminal you can leave open.**

   ```bash
   sudo /opt/dahouselab/scripts/knowledge/build-knowledge-base.sh
   ```

   Expected: it logs each document, then the index size, then `registered with Nextcloud`. **This
   takes hours on a Pi 4** — local embeddings on an ARM CPU. Run it when you do not need the
   platform responsive, or accept the `nice`/`ionice` throttling and let it work.

5. **Install the timer.**

   ```bash
   sudo cp /opt/dahouselab/infrastructure/configs/systemd/dahouselab-knowledge.{service,timer} \
     /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now dahouselab-knowledge.timer
   systemctl list-timers dahouselab-knowledge.timer
   ```

   Expected: the timer is listed with its next run at 04:30.

6. **Wire the dead-man monitor.** A build that stops happening fails silently otherwise — the index
   just quietly goes stale.

   In Uptime Kuma create a **Push** monitor named `knowledge-nightly` with a **26 h** interval
   (one day plus slack), Telegram attached. Then:

   ```bash
   sudo install -d -m 700 /etc/dahouselab
   sudo tee /etc/dahouselab/knowledge-push.env >/dev/null <<'ENVEOF'
   KUMA_PUSH_URL=https://status.dahub.casa/api/push/<token>
   ENVEOF
   sudo chmod 600 /etc/dahouselab/knowledge-push.env
   sudo systemctl start dahouselab-knowledge.service
   ```

   Expected: the monitor turns green after the run. Same pattern as the backup's dead-man switch.

7. **Workstation side.** Install the reader CLI at the **same version** as the image — they share
   the file format:

   ```bash
   npm install -g memvid-cli@2.0.160
   memvid stats ~/Nextcloud/Knowledge/knowledge.mv2
   memvid ask ~/Nextcloud/Knowledge/knowledge.mv2 "<something you know is in your documents>"
   ```

   Expected: a chunk count that matches roughly what was ingested, and an answer citing a source.
   Adjust the path to wherever your Nextcloud client syncs.

   Nothing else is needed for Claude Code: it has a shell, so it can run `memvid ask` directly.
   [`docs/ai-prompts/base-de-conocimiento.md`](../ai-prompts/base-de-conocimiento.md) is what tells
   an assistant the base exists.

## Verification

- [ ] `docker run --rm dahouselab/memvid:2.0.160 --version` → `2.0.160`
- [ ] Dry-run excludes Nextcloud internals: the `grep -c` in step 3 → `0`
- [ ] `ls -lh ${DATA_ROOT}/knowledge/knowledge.mv2` → exists, non-trivial size
- [ ] Source untouched — the job must not be able to write user files:
      `grep -n ':ro' /opt/dahouselab/scripts/knowledge/build-knowledge-base.sh` → the Nextcloud
      mount is read-only
- [ ] `systemctl list-timers dahouselab-knowledge.timer` → scheduled for 04:30
- [ ] Kuma `knowledge-nightly` monitor green after a manual run
- [ ] On the workstation: `~/Nextcloud/Knowledge/knowledge.mv2` present after sync
- [ ] `memvid ask <path> "<known fact>"` → correct answer with a source
- [ ] Ask Claude something only your documents contain → it runs `memvid ask` and answers from it
- [ ] **Second run is fast**: `sudo systemctl start dahouselab-knowledge.service` finishes in
      minutes, not hours — proof the incremental state file works
- [ ] The platform is healthy during a build: `free -h` ≥ 1.5 GiB, other services responsive

## Rollback

```bash
sudo systemctl disable --now dahouselab-knowledge.timer
sudo rm /etc/systemd/system/dahouselab-knowledge.{service,timer}
sudo systemctl daemon-reload
```

The index is a derived artifact: deleting `${DATA_ROOT}/knowledge` loses nothing but the time to
rebuild it. Remove the published copy from Nextcloud too if you want it off your devices, then
`docker exec -u www-data nextcloud php occ files:scan --path="<user>/files/Knowledge"` so Nextcloud
notices the deletion.

## Troubleshooting

| Symptom                                        | Likely cause                                 | Action                                                              |
| ---------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------- |
| Index never appears on the workstation         | `occ files:scan` was skipped or failed       | The single most common failure. Re-run the script; Nextcloud cannot see files written underneath it |
| `image ... missing`                            | Image not built on this host                 | Step 1 — the image is built locally, not pulled                      |
| Dry-run lists `files_versions/` paths          | Exclusion list not matching                  | Do **not** build. Fix the `-prune` clause first                      |
| First run still going after many hours         | Expected on a Pi 4 with a large library      | Let it finish; it is `nice`d. If unacceptable, narrow `EXTENSIONS` or build on the workstation (ADR-0016 Option B) |
| Every run is slow, not just the first          | State file not being written                 | Check `${DATA_ROOT}/knowledge/.ingested-state` exists and grows      |
| Some documents never appear in answers         | Extension not in the allowlist               | `EXTENSIONS` at the top of the script — one line                     |
| `memvid stats` fails on the workstation        | CLI/image version mismatch                   | Both must be `2.0.160`; the file format is version-bound             |
| Kuma monitor red, no obvious failure           | The unit failed before the push              | `journalctl -u dahouselab-knowledge -n 100`                          |
| Answers cite an old version of a document      | The edited file's mtime did not change       | Touch the file and re-run                                            |

## Automation opportunities

- The script **is** the automation; what remains manual is step 2 (one variable) and step 6 (the
  push token). Both belong in a future `scripts/bootstrap/` host-config step.
- Building the image could join the same bootstrap path, alongside `docker network create proxy`.
- The dry-run exclusion assertion in step 3 is a good candidate for
  [run-health-checks](run-health-checks.md) — a regression there is silent and expensive.

## Future improvements

- **Paperless-ngx as a second source** once deployed: OCR'd and tagged, a far better corpus than
  raw files.
- **Excluding the `.mv2` from Nextcloud's own versioning** — a binary that changes nightly generates
  version history nobody wants.
- **Excluding `${DATA_ROOT}/knowledge` from backups**: it is fully regenerable, and it is copied
  into Nextcloud anyway ([docs/backup](../backup/README.md)).
- A freshness signal in the index itself, so a stale base is visible when queried rather than
  only in Kuma.
