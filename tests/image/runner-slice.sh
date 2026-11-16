#!/usr/bin/bash
# runner.slice parses cleanly and carries its default limits.
set -euo pipefail

# verify only warns, exiting 0, on values it ignores, such as a bad limit.
out=$(systemd-analyze verify runner.slice 2>&1)
if [[ -n "${out}" ]]; then
	echo "error: systemd-analyze verify runner.slice:" >&2
	echo "${out}" >&2
	exit 1
fi

config=$(cat /usr/lib/systemd/system/runner.slice.d/*.conf)
for key in MemoryHigh MemoryMax CPUWeight; do
	if ! grep -q "^${key}=" <<<"${config}"; then
		echo "error: runner.slice sets no ${key}" >&2
		exit 1
	fi
done
