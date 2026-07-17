#!/usr/bin/env bash
# ==============================================================================
# run-backup.sh — full platform backup
#
# Implements: docs/runbooks/execute-backup.md (this script IS that runbook)
# Usage:      sudo /opt/dahouselab/scripts/backup/run-backup.sh
# Exit codes: 0 = backup complete and verified; non-zero = FAILED, do not trust the set
#
# What it does:
#   1. Guards: root, env, backup disk mounted AND a distinct device, disk space
#   2. Dumps SQLite DBs with the online backup API (vaultwarden)
#   3. Briefly stops uptime-kuma (embedded MariaDB v2 — no safe hot-dump) around the rsync
#   4. Rsyncs CONFIG_ROOT and DATA_ROOT into a dated, hardlink-rotated set
#   5. Manifest + SHA256SUMS, verify, promote `latest`, prune to 7 daily sets
# ==============================================================================
set -euo pipefail

ENV_FILE="/opt/dahouselab/.env"
RETENTION_DAILY=7

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

# ------------------------------------------------------------------ guards ---
[ "$(id -u)" -eq 0 ] || fail "must run as root (sudo)"
[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE"
set -a; # shellcheck disable=SC1090
source "$ENV_FILE"; set +a
: "${CONFIG_ROOT:?}" "${DATA_ROOT:?}" "${BACKUP_ROOT:?}"

findmnt --target "$BACKUP_ROOT" >/dev/null || fail "$BACKUP_ROOT is not a mountpoint — backup disk not mounted, refusing to run"
[ "$(findmnt -n -o SOURCE --target "$BACKUP_ROOT")" != "$(findmnt -n -o SOURCE --target "$DATA_ROOT")" ] \
  || fail "backup target is on the SAME device as the data — refusing to run"

used_pct=$(df --output=pcent "$BACKUP_ROOT" | tail -1 | tr -dc '0-9')
[ "$used_pct" -lt 90 ] || fail "backup disk ${used_pct}% full — prune or replace before running"
[ "$used_pct" -lt 80 ] || log "WARNING: backup disk ${used_pct}% full (threshold 80%)"

command -v sqlite3 >/dev/null || fail "sqlite3 not installed on the host (sudo apt-get install -y sqlite3)"

BACKUP_DATE=$(date +%F)
BACKUP_SET="${BACKUP_ROOT}/dahouselab/daily/${BACKUP_DATE}"
LATEST_LINK="${BACKUP_ROOT}/dahouselab/latest"
mkdir -p "$BACKUP_SET"
log "backup set: $BACKUP_SET"

# ------------------------------------------------------- database dumps ------
# vaultwarden — SQLite online backup API (never cp a live SQLite file)
if [ -f "${DATA_ROOT}/vaultwarden/db.sqlite3" ]; then
  mkdir -p "${DATA_ROOT}/vaultwarden/db-dumps"
  sqlite3 "${DATA_ROOT}/vaultwarden/db.sqlite3" \
    ".backup '${DATA_ROOT}/vaultwarden/db-dumps/vaultwarden-${BACKUP_DATE}.sqlite3'"
  [ "$(sqlite3 "${DATA_ROOT}/vaultwarden/db-dumps/vaultwarden-${BACKUP_DATE}.sqlite3" 'PRAGMA integrity_check;')" = "ok" ] \
    || fail "vaultwarden dump failed integrity_check"
  log "vaultwarden: sqlite dump OK"
fi

# Future Postgres services (nextcloud, immich, paperless-ngx) hook in here:
# docker exec <svc>-postgres pg_dump -U <user> -Fc -d <db> > "${DATA_ROOT}/<svc>/db-dumps/<svc>-${BACKUP_DATE}.dump"

# ------------------------------------------------------------- rsync ---------
# uptime-kuma v2 uses an EMBEDDED MariaDB — no safe hot-copy. Stop it only for
# the duration of the rsync (monitors pause; acceptable, documented tradeoff).
kuma_was_running=false
if docker ps --format '{{.Names}}' | grep -q '^uptime-kuma$'; then
  kuma_was_running=true
  log "stopping uptime-kuma for a consistent copy (monitors pause)"
  docker stop uptime-kuma >/dev/null
fi
restart_kuma() {
  if $kuma_was_running; then
    docker start uptime-kuma >/dev/null && log "uptime-kuma restarted"
    kuma_was_running=false   # idempotent: trap + explicit call must not double-start
  fi
  return 0
}
trap restart_kuma EXIT   # kuma comes back even if rsync fails

if [ -e "$LATEST_LINK" ]; then
  rsync -aHAX --delete --link-dest="${LATEST_LINK}/config" "${CONFIG_ROOT}/" "${BACKUP_SET}/config/"
  rsync -aHAX --delete --link-dest="${LATEST_LINK}/data"   "${DATA_ROOT}/"   "${BACKUP_SET}/data/"
else
  log "first run: no previous set to hardlink against (full copy)"
  rsync -aHAX --delete "${CONFIG_ROOT}/" "${BACKUP_SET}/config/"
  rsync -aHAX --delete "${DATA_ROOT}/"   "${BACKUP_SET}/data/"
fi
log "rsync complete"

restart_kuma
trap - EXIT

# --------------------------------------------------- manifest + verify -------
{
  echo "backup_date=${BACKUP_DATE}"
  echo "host=$(hostname)"
  echo "created=$(date -Is)"
  du -sb "${BACKUP_SET}/config" "${BACKUP_SET}/data"
  echo "file_count=$(find "$BACKUP_SET" -type f | wc -l)"
} > "${BACKUP_SET}/MANIFEST.txt"

find "${BACKUP_SET}/data" -path '*/db-dumps/*' -name "*${BACKUP_DATE}*" -type f -exec sha256sum {} + \
  > "${BACKUP_SET}/SHA256SUMS" || true
if [ -s "${BACKUP_SET}/SHA256SUMS" ]; then
  sha256sum -c --quiet "${BACKUP_SET}/SHA256SUMS" || fail "dump checksum verification FAILED"
  log "checksums verified: $(wc -l < "${BACKUP_SET}/SHA256SUMS") dump(s)"
else
  log "note: no db dumps found to checksum"
fi

ln -sfn "$BACKUP_SET" "$LATEST_LINK"
log "promoted to latest: $(readlink "$LATEST_LINK")"

# ------------------------------------------------------------- retention -----
mapfile -t old_sets < <(ls -1d "${BACKUP_ROOT}"/dahouselab/daily/*/ 2>/dev/null | head -n -"$RETENTION_DAILY")
if [ "${#old_sets[@]}" -gt 0 ]; then
  log "pruning ${#old_sets[@]} set(s) beyond ${RETENTION_DAILY}-day retention:"
  printf '  %s\n' "${old_sets[@]}"
  rm -rf -- "${old_sets[@]}"
fi

log "BACKUP OK — $(du -sh "$BACKUP_SET" | cut -f1) in $BACKUP_SET"
