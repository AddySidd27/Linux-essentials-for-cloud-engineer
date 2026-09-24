#!/usr/bin/env bash
# disk-alert.sh - list filesystems above a usage threshold.
#
# Usage: disk-alert.sh [threshold-percent]
# Example: disk-alert.sh 80
#
# Checks space and inode usage on real filesystems (ignores tmpfs, overlay,
# squashfs). Exit code: 0 = all below threshold, 1 = at least one above.

set -euo pipefail

threshold="${1:-80}"

if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [threshold-percent]" >&2
  exit 2
fi

exclude=(-x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs)
alerts=0

while read -r target pcent ipcent; do
  used=${pcent%\%}
  iused=${ipcent%\%}
  [[ "$iused" == "-" ]] && iused=0
  if (( used >= threshold )); then
    echo "ALERT space  $target ${used}% used"
    alerts=$((alerts + 1))
  fi
  if (( iused >= threshold )); then
    echo "ALERT inodes $target ${iused}% used"
    alerts=$((alerts + 1))
  fi
done < <(df --output=target,pcent,ipcent "${exclude[@]}" | tail -n +2)

if (( alerts == 0 )); then
  echo "OK: all filesystems below ${threshold}%"
  exit 0
fi

exit 1
