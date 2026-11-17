#!/usr/bin/bash
# Helpers for the libvirt VM tests, sourced by them. The caller sets
# VM_NAME, and may set BCVK, BCVK_CONNECTION, PODMAN and BOOT_WAIT_SECS.

BCVK="${BCVK:-bcvk}"
BCVK_CONNECTION="${BCVK_CONNECTION:-qemu:///session}"
PODMAN="${PODMAN:-podman}"
BOOT_WAIT_SECS="${BOOT_WAIT_SECS:-300}"

# Builds BASE plus a file PATH holding MARKER, tagged as TAG; prints the ID.
# The VM tests install such a derived build with vm_install: in CI, bootc
# 1.17.1 failed to install the loaded image itself with --target-transport
# containers-storage ("Invalid splitstream content type"). Whether the extra
# layer or --update-from-host avoids that is not yet known.
derive_image() {
	local base=$1 marker=$2 path=$3 tag=$4 dir id
	dir=$(mktemp -d) || return
	printf 'FROM %s\nRUN echo %s > %s\n' "${base}" "${marker}" "${path}" >"${dir}/Containerfile"
	id=$("${PODMAN}" build --quiet --tag "${tag}" "${dir}") || { rm -rf "${dir}"; return 1; }
	rm -rf "${dir}"
	echo "${id}"
}

# Installs an image from the host's containers-storage into VM_NAME and
# boots it; further arguments (sizes, the image) go to `bcvk libvirt run`.
# --update-from-host binds that storage so bootc upgrade and switch in the
# VM see images built on the host later.
vm_install() {
	"${BCVK}" libvirt --connect "${BCVK_CONNECTION}" run --name "${VM_NAME}" --update-from-host \
		--filesystem btrfs --detach --ssh-wait "$@"
}

vm() {
	if [[ -n "${VM_CALL_TIMEOUT:-}" ]]; then
		timeout --kill-after=2s "${VM_CALL_TIMEOUT}s" "${BCVK}" libvirt --connect "${BCVK_CONNECTION}" ssh "${VM_NAME}" "$@"
	else
		"${BCVK}" libvirt --connect "${BCVK_CONNECTION}" ssh "${VM_NAME}" "$@"
	fi
}

# Waits for a new boot ID, so a slow shutdown is not mistaken for the reboot.
reboot_and_wait() {
	local old_boot new_boot remaining deadline=$((SECONDS + BOOT_WAIT_SECS))
	old_boot=$(vm 'cat /proc/sys/kernel/random/boot_id')
	vm 'systemctl reboot' || true
	while true; do
		remaining=$((deadline - SECONDS))
		if ((remaining <= 0)); then
			echo "error: ${VM_NAME} did not come back within ${BOOT_WAIT_SECS}s" >&2
			return 1
		fi
		# Bound each poll by the remaining budget, including an unreachable SSH.
		if new_boot=$(VM_CALL_TIMEOUT="${remaining}" vm 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null) && [[ -n "${new_boot}" && "${new_boot}" != "${old_boot}" ]]; then
			return 0
		fi
		remaining=$((deadline - SECONDS))
		if ((remaining > 0)); then sleep "$((remaining < 5 ? remaining : 5))"; fi
	done
}
