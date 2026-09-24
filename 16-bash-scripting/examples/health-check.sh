#!/usr/bin/env bash
# health-check.sh - basic health check for a Linux server.
#
# Usage: health-check.sh [service ...]
# Example: health-check.sh nginx ssh
#
# Checks load, memory, root disk usage, and the given systemd services.
# Exit code: 0 = healthy, 1 = at least one check failed.
# Thresholds can be changed with environment variables:
#   LOAD_PER_CPU (default 2), MEM_PCT (default 90), DISK_PCT (default 85)

set -euo pipefail

LOAD_PER_CPU="${LOAD_PER_CPU:-2}"
MEM_PCT="${MEM_PCT:-90}"
DISK_PCT="${DISK_PCT:-85}"

failures=0

report() {
  local status="$1"
  shift
  printf '%s %-5s %s\n' "$(date -Is)" "$status" "$*"
  if [[ "$status" != "OK" ]]; then
    failures=$((failures + 1))
  fi
}

# Load average (1 minute) compared with number of CPUs
cpus=$(nproc)
load=$(cut -d' ' -f1 /proc/loadavg)
if awk -v l="$load" -v c="$cpus" -v f="$LOAD_PER_CPU" 'BEGIN { exit !(l > c * f) }'; then
  report FAIL "load $load ($cpus CPUs)"
else
  report OK "load $load ($cpus CPUs)"
fi

# Memory in use, based on MemAvailable
mem_used=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%d", (t-a)*100/t}' /proc/meminfo)
if (( mem_used >= MEM_PCT )); then
  report FAIL "memory ${mem_used}% used"
else
  report OK "memory ${mem_used}% used"
fi

# Root filesystem usage
disk_used=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if (( disk_used >= DISK_PCT )); then
  report FAIL "/ ${disk_used}% used"
else
  report OK "/ ${disk_used}% used"
fi

# Services passed as arguments
for svc in "$@"; do
  state=$(systemctl is-active "$svc" 2>/dev/null || true)
  if [[ "$state" == "active" ]]; then
    report OK "service $svc active"
  else
    report FAIL "service $svc ${state:-unknown}"
  fi
done

if (( failures > 0 )); then
  echo "RESULT: $failures check(s) failed"
  exit 1
fi

echo "RESULT: healthy"
