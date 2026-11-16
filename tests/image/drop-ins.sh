#!/usr/bin/bash
# Every package in custom/packages/*.txt is installed and every unit in
# custom/units/*.enable is enabled. `just image-test` mounts custom/ at
# /ctx/custom, as the build does.
set -euo pipefail
shopt -s nullglob

entries() {
	sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$@"
}

package_files=(/ctx/custom/packages/*.txt)
unit_files=(/ctx/custom/units/*.enable)
if ((${#package_files[@]} == 0 || ${#unit_files[@]} == 0)); then
	echo "error: no package or unit lists under /ctx/custom" >&2
	exit 1
fi

mapfile -t packages < <(entries "${package_files[@]}")
rpm -q "${packages[@]}"

mapfile -t units < <(entries "${unit_files[@]}")
for unit in "${units[@]}"; do
	state=$(systemctl is-enabled "${unit}" || true)
	if [[ "${state}" != enabled ]]; then
		echo "error: ${unit} is '${state}', expected enabled" >&2
		exit 1
	fi
done
