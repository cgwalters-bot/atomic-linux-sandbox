#!/usr/bin/bash
# The build's dnf5 settings (keepcache=1, install_weak_deps=0) must not leak
# into the image, where derived images would inherit them.
set -euo pipefail

config=$(dnf5 --dump-main-config)
for expected in 'keepcache = 0' 'install_weak_deps = 1'; do
	if ! grep -qxF "${expected}" <<<"${config}"; then
		echo "error: dnf5 main config lacks '${expected}'" >&2
		exit 1
	fi
done
