#!/bin/sh
# Samples LeanBattery once per second; prints mean CPU %, idle wakeups per minute and last memory reading.
# top reports IDLEW as a running total, so wakeups/min = (last - first) / seconds * 60.
# Usage: scripts/cpu-check.sh [samples]   (default 600 = 10 minutes)
set -eu
samples="${1:-600}"
pid="$(pgrep -nx LeanBattery)" || { echo "LeanBattery is not running" >&2; exit 1; }
top -pid "$pid" -stats cpu,idlew,mem -l "$((samples + 1))" -s 1 | awk '
	$1 ~ /^[0-9.]+$/ {
		if (seen++) { cpu += $1; count++ } else { firstWakeups = $2 }
		lastWakeups = $2
		memory = $3
	}
	END {
		if (count == 0) { print "no samples collected (did LeanBattery exit?)" > "/dev/stderr"; exit 1 }
		sub(/[+-]$/, "", memory)
		printf "samples=%d mean_cpu=%.2f%% idle_wakeups_per_min=%.1f memory=%s\n", count, cpu / count, (lastWakeups - firstWakeups) / count * 60, memory
	}'
