#!/usr/bin/bash
# The debug tools from custom/packages/debug-tools.txt are on PATH and run,
# and sysstat's background collection stays disabled.
set -euo pipefail

strace -V >/dev/null
ltrace -V >/dev/null
perf --version >/dev/null
bpftrace --version >/dev/null
for binary in iostat mpstat pidstat sar; do
	"${binary}" -V >/dev/null
done

for unit in sysstat.service sysstat-collect.timer sysstat-summary.timer; do
	state=$(systemctl is-enabled "${unit}" || true)
	if [[ "${state}" != disabled ]]; then
		echo "error: ${unit} is '${state}', expected disabled" >&2
		exit 1
	fi
done
