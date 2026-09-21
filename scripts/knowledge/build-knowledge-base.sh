#!/usr/bin/env bash
# ==============================================================================
# build-knowledge-base.sh — rebuild the personal knowledge base from Nextcloud
#
# Implements: docs/runbooks/build-knowledge-base.md (this script IS that runbook)
# Decision:   docs/decisions/0016-memvid-personal-knowledge-base.md
# Usage:      sudo /opt/dahouselab/scripts/knowledge/build-knowledge-base.sh [--dry-run]
# Exit codes: 0 = index built and delivered; non-zero = FAILED, index may be stale
#
# What it does:
#   1. Guards: root, env, image present, Nextcloud data readable, disk space
#   2. Enumerates candidate documents (allowlist of extensions, minus Nextcloud's
#      internal directories) across every Nextcloud user
#   3. Skips anything already ingested and unchanged (path + mtime state file)
#   4. Ingests the remainder with memvid, in a container, read-only on the source
#   5. Publishes the .mv2 into Nextcloud and registers it with `occ files:scan`
#
# Why a script and not a service: memvid has no daemon. See ADR-0016.
# ==============================================================================
set -euo pipefail

ENV_FILE="/opt/dahouselab/.env"
MEMVID_IMAGE="dahouselab/memvid:2.0.160"

# --- Tunables ----------------------------------------------------------------
# Extensions to ingest. "All of Nextcloud" means all TEXT-BEARING files: memvid
# cannot usefully embed a photo or a video without the optional CLIP models, and
# on a Pi 4 the attempt is ruinously slow. Add extensions here if you need more.
EXTENSIONS="pdf md txt docx odt rtf csv epub"

# Nextcloud user whose folder receives the finished index (it syncs from there).
# Must be a real user directory under <nextcloud data>/<user>/files/.
KNOWLEDGE_TARGET_USER="${KNOWLEDGE_TARGET_USER:-}"

# Folder inside that user's Nextcloud files where the index is published.
KNOWLEDGE_TARGET_DIR="Knowledge"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# ------------------------------------------------------------------ guards ---
[ "$(id -u)" -eq 0 ] || fail "must run as root (sudo) — reads every Nextcloud user's files"
[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE"
set -a; # shellcheck disable=SC1090
source "$ENV_FILE"; set +a
: "${DATA_ROOT:?}"

NC_DATA="${DATA_ROOT}/nextcloud/data"
KB_DIR="${DATA_ROOT}/knowledge"
KB_FILE="${KB_DIR}/knowledge.mv2"
STATE_FILE="${KB_DIR}/.ingested-state"
CACHE_DIR="${KB_DIR}/.cache"

[ -d "$NC_DATA" ] || fail "Nextcloud data not found at $NC_DATA — is nextcloud deployed?"

if ! $DRY_RUN; then
  docker image inspect "$MEMVID_IMAGE" >/dev/null 2>&1 \
    || fail "image $MEMVID_IMAGE missing — build it: docker build -t $MEMVID_IMAGE /opt/dahouselab/infrastructure/images/memvid"
  [ -n "$KNOWLEDGE_TARGET_USER" ] \
    || fail "KNOWLEDGE_TARGET_USER is unset — set it at the top of this script (the Nextcloud user whose folder receives the index)"
  [ -d "${NC_DATA}/${KNOWLEDGE_TARGET_USER}/files" ] \
    || fail "no such Nextcloud user: ${KNOWLEDGE_TARGET_USER} (looked for ${NC_DATA}/${KNOWLEDGE_TARGET_USER}/files)"

  avail_mb=$(df -Pm "$DATA_ROOT" | awk 'NR==2 {print $4}')
  [ "$avail_mb" -gt 2048 ] || fail "less than 2 GB free on ${DATA_ROOT} — refusing to build"

  install -d -o 1000 -g 1000 "$KB_DIR" "$CACHE_DIR"
  touch "$STATE_FILE"
fi

# ------------------------------------------------- enumerate candidates ------
# Excluded, always: Nextcloud's internal trees. files_versions and files_trashbin
# hold copies of the very documents we are indexing — ingesting them would bury
# the current version of every file under its own history. appdata_*/cache hold
# thumbnails and previews, which are not documents at all.
log "scanning ${NC_DATA} (users: $(find "$NC_DATA" -maxdepth 2 -type d -name files 2>/dev/null | wc -l | tr -d ' '))"

ext_expr=()
for e in $EXTENSIONS; do ext_expr+=( -iname "*.${e}" -o ); done
unset 'ext_expr[${#ext_expr[@]}-1]'   # drop the trailing -o

mapfile -t candidates < <(
  find "$NC_DATA" \
      -type d \( -name 'files_versions' \
              -o -name 'files_trashbin' \
              -o -name 'files_external' \
              -o -name 'cache' \
              -o -name 'uploads' \
              -o -name 'appdata_*' \) -prune -o \
      -type f \( "${ext_expr[@]}" \) -print 2>/dev/null | sort
)

log "candidate documents: ${#candidates[@]}"
[ "${#candidates[@]}" -gt 0 ] || { log "nothing to ingest — done"; exit 0; }

# ---------------------------------------------------- incremental filter -----
# State line format: <mtime-epoch>:<absolute path>. A file whose mtime changed is
# re-ingested; memvid deduplicates by content on its side.
new_files=()
for f in "${candidates[@]}"; do
  mt=$(stat -c %Y "$f" 2>/dev/null) || continue
  if ! grep -qxF "${mt}:${f}" "$STATE_FILE" 2>/dev/null; then
    new_files+=( "$f" )
  fi
done

log "new or changed since last run: ${#new_files[@]}"

if $DRY_RUN; then
  log "--dry-run: the following would be ingested (no changes made)"
  printf '  %s\n' "${new_files[@]}"
  exit 0
fi

[ "${#new_files[@]}" -gt 0 ] || { log "index already current — nothing to do"; exit 0; }

# ------------------------------------------------------------- ingest --------
# Nextcloud data is mounted READ-ONLY: this job must never be able to alter user
# files. Only ${KB_DIR} is writable. Embeddings are computed locally (BGE), so no
# document content leaves the host (ADR-0016).
log "ingesting with $MEMVID_IMAGE (local embedder; first run is slow on ARM)"

for f in "${new_files[@]}"; do
  rel="${f#"${NC_DATA}"/}"
  log "  + ${rel}"
  nice -n 10 ionice -c 3 \
    docker run --rm \
      -v "${NC_DATA}:/src:ro" \
      -v "${KB_DIR}:/out" \
      -v "${CACHE_DIR}:/cache" \
      "$MEMVID_IMAGE" \
      put /out/knowledge.mv2 --input "/src/${rel}" --embedding --vector-compression \
    || { log "  ! failed on ${rel} — continuing"; continue; }

  printf '%s:%s\n' "$(stat -c %Y "$f")" "$f" >> "$STATE_FILE"
done

[ -f "$KB_FILE" ] || fail "no index produced at $KB_FILE — every ingest failed"
log "index built: $(du -h "$KB_FILE" | cut -f1)"

# ------------------------------------------------------------ publish --------
# THE STEP THAT SILENTLY BREAKS EVERYTHING IF SKIPPED: Nextcloud does not notice
# files written underneath it. Without files:scan the index never reaches any
# client, while every other check still looks healthy.
DEST_DIR="${NC_DATA}/${KNOWLEDGE_TARGET_USER}/files/${KNOWLEDGE_TARGET_DIR}"
install -d -o 33 -g 33 "$DEST_DIR"
cp "$KB_FILE" "${DEST_DIR}/knowledge.mv2"
chown 33:33 "${DEST_DIR}/knowledge.mv2"   # www-data inside the nextcloud container
log "published to ${DEST_DIR}/knowledge.mv2"

if docker ps --format '{{.Names}}' | grep -q '^nextcloud$'; then
  docker exec -u www-data nextcloud php occ files:scan \
    --path="${KNOWLEDGE_TARGET_USER}/files/${KNOWLEDGE_TARGET_DIR}" \
    || fail "occ files:scan failed — the index will NOT sync to any client until it succeeds"
  log "registered with Nextcloud — it will sync to your devices"
else
  fail "nextcloud container not running — index copied but NOT registered; re-run when it is up"
fi

log "KNOWLEDGE BASE OK — $(du -h "$KB_FILE" | cut -f1), ${#new_files[@]} document(s) added this run"
