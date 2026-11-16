#!/usr/bin/bash
# bootc-fetch-apply-updates only stages updates, never applies them with a
# reboot, and rpm-ostree's automatic updates stay off. drop-ins.sh checks
# that the timer is enabled.
set -euo pipefail
shopt -s nullglob

service=/usr/lib/systemd/system/bootc-fetch-apply-updates.service

# The last ExecStart= across the unit and its drop-ins is the one that runs.
exec_start=$(cat "${service}" "${service}".d/*.conf | grep '^ExecStart=' | tail -n1)
if [[ "${exec_start}" != 'ExecStart=/usr/bin/bootc upgrade --quiet' ]]; then
	echo "error: effective ExecStart is not stage-only: ${exec_start}" >&2
	exit 1
fi

state=$(systemctl is-enabled rpm-ostreed-automatic.timer || true)
if [[ "${state}" == enabled ]]; then
	echo "error: rpm-ostreed-automatic.timer is enabled alongside bootc's timer" >&2
	exit 1
fi
