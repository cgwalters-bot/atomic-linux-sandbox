#!/usr/bin/bash
# Host services from custom/*/host-services.*: restic backups stay inert until
# configured, and the host carries no Node.js (agents run in VMs instead).
set -euo pipefail

systemd-analyze verify --man=no restic-backup.service restic-backup.timer
if systemd-analyze condition --unit=restic-backup.service >/dev/null; then
	echo "error: restic-backup.service would run without /etc/restic-backup" >&2
	exit 1
fi

if rpm -q nodejs >/dev/null; then
	echo "error: nodejs is installed" >&2
	exit 1
fi
for binary in node nodejs; do
	if path=$(command -v "${binary}"); then
		echo "error: ${binary} is installed at ${path}" >&2
		exit 1
	fi
done
