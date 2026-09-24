#!/usr/bin/env bash
# backup-dir.sh - create a dated, compressed backup of a directory.
#
# Usage: backup-dir.sh <source-dir> <backup-dir> [copies-to-keep]
# Example: sudo backup-dir.sh /etc /var/backups/etc 7
#
# - Writes <backup-dir>/<name>-YYYY-MM-DD_HHMMSS.tar.gz
# - Keeps the newest N archives (default 7) and deletes older ones
# - Refuses to run twice at the same time (lock file)
# - Logs to the system journal with the tag "backup-dir"

set -euo pipefail

src="${1:?Usage: $0 <source-dir> <backup-dir> [copies-to-keep]}"
dest="${2:?Usage: $0 <source-dir> <backup-dir> [copies-to-keep]}"
keep="${3:-7}"

log() {
  echo "$*"
  logger -t backup-dir -- "$*"
}

if [[ ! -d "$src" ]]; then
  log "ERROR: source $src is not a directory"
  exit 1
fi

if ! [[ "$keep" =~ ^[0-9]+$ ]] || (( keep < 1 )); then
  log "ERROR: copies-to-keep must be a positive number"
  exit 1
fi

mkdir -p "$dest"

# Only one backup at a time
exec 9>"$dest/.backup.lock"
if ! flock -n 9; then
  log "ERROR: another backup is running for $dest"
  exit 1
fi

name=$(basename "$src")
stamp=$(date +%F_%H%M%S)
archive="$dest/${name}-${stamp}.tar.gz"

# -C changes to the parent so the archive contains "etc/..." not "/etc/..."
tar -czf "$archive" -C "$(dirname "$src")" "$name"

size=$(du -h "$archive" | cut -f1)
log "created $archive ($size)"

# Delete old archives beyond the number to keep (newest first)
mapfile -t old < <(
  find "$dest" -maxdepth 1 -type f -name "${name}-*.tar.gz" -printf '%T@ %p\n' \
    | sort -rn | tail -n +"$((keep + 1))" | cut -d' ' -f2-
)
for file in "${old[@]}"; do
  rm -f -- "$file"
  log "removed old backup $file"
done

log "done, keeping $keep most recent backups in $dest"
