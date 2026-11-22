#!/usr/bin/bash
# Helpers for the libvirt VM tests, sourced by them. The caller sets
# VM_NAME, and may set BCVK, BCVK_CONNECTION, PODMAN, BOOT_WAIT_SECS and
# EXPECT_BOOTLOADER.

BCVK="${BCVK:-bcvk}"
BCVK_CONNECTION="${BCVK_CONNECTION:-qemu:///session}"
PODMAN="${PODMAN:-podman}"
BOOT_WAIT_SECS="${BOOT_WAIT_SECS:-300}"
# The bootloader the installed system must have been started by, as bootc
# names it: grub or systemd. The image installs GRUB; a build that switches
# the default changes this too.
EXPECT_BOOTLOADER="${EXPECT_BOOTLOADER:-grub}"
# Deployments whose kernel and initramfs must fit the ESP together, as
# systemd-boot keeps them there: the booted one, its update and a rollback.
readonly ESP_DEPLOYMENTS=3

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
	local old_boot
	old_boot=$(vm 'cat /proc/sys/kernel/random/boot_id')
	vm 'systemctl reboot' || true
	wait_for_boot "${old_boot}"
}

# Runs as root in the UEFI guest. Use bootc's JSON for the assertion; the
# raw LoaderInfo and bootctl's human-readable status are diagnostics (for
# example, bootctl can report "GRUB 2.12" rather than bootc's "grub").
report_bootloader() {
	local want=$1 loader_info bootc_name
	if [[ ! -d /sys/firmware/efi/efivars ]]; then
		echo "error: not booted with UEFI, or efivarfs is not mounted" >&2
		return 1
	fi
	if ! bootctl status --no-pager; then
		echo "warning: bootctl status failed" >&2
	fi
	if command -v mokutil >/dev/null; then
		mokutil --sb-state || true
	else
		echo "mokutil is not installed; see bootctl's Secure Boot line above"
	fi
	loader_info=$(tail -c +5 /sys/firmware/efi/efivars/LoaderInfo-4a67b082-0a4c-41cf-b6c7-5ea2e7c56d2b 2>/dev/null | tr -d '\0' || true)
	printf 'LoaderInfo: "%s"\n' "${loader_info}"
	if ! bootc_name=$(bootc status --format=json | jq -er '.status.booted.composefs.bootloader'); then
		echo "error: could not read the booted composefs bootloader from bootc status" >&2
		return 1
	fi
	printf 'Bootloader: bootc %s; expected %s\n' "${bootc_name}" "${want}"
	if [[ "${bootc_name}" != "${want}" ]]; then
		echo "error: bootc says the bootloader is '${bootc_name}', expected '${want}'" >&2
		return 1
	fi
}

# Runs as root in the VM. Prints the ESP's size and free space and the size
# of the kernel and initramfs the image ships, and fails if $1 deployments
# of them would not fit the ESP: systemd-boot keeps kernels there, and
# to-existing-root reuses the host's ESP (512 MiB in its test) rather than
# making a 2 GiB one as to-disk does.
report_esp() {
	local deployments=$1 esp_dev esp mounted=0 size avail kver kernel initrd payload
	esp_dev=$(lsblk -nrpo PATH,PARTTYPE | awk '$2 == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" { print $1; exit }')
	if [[ -z "${esp_dev}" ]]; then
		echo "error: no EFI system partition found" >&2
		return 1
	fi
	# bootc leaves the ESP unmounted on a composefs system; findmnt then exits 1.
	esp=$(findmnt -nro TARGET --source "${esp_dev}" | head -n1 || true)
	if [[ -z "${esp}" ]]; then
		esp=/run/atomic-linux-esp
		mkdir -p "${esp}"
		mount -o ro "${esp_dev}" "${esp}"
		mounted=1
	fi
	size=$(df -B1 --output=size,avail "${esp}" | tail -n1)
	if ((mounted)); then
		umount "${esp}"
	fi
	read -r size avail <<<"${size}"
	kver=$(uname -r)
	kernel=$(stat -c %s "/usr/lib/modules/${kver}/vmlinuz")
	initrd=$(stat -c %s "/usr/lib/modules/${kver}/initramfs.img")
	payload=$((kernel + initrd))
	printf 'ESP %s: %s MiB, %s MiB free; kernel %s: vmlinuz %s MiB + initramfs %s MiB = %s MiB a deployment\n' \
		"${esp_dev}" "$((size >> 20))" "$((avail >> 20))" "${kver}" "$((kernel >> 20))" "$((initrd >> 20))" "$((payload >> 20))"
	if ((deployments * payload > size)); then
		echo "error: ${deployments} deployments need $((deployments * payload >> 20)) MiB, more than the $((size >> 20)) MiB ESP" >&2
		return 1
	fi
}

# Prints what booted VM_NAME and the ESP's headroom, and fails unless
# EXPECT_BOOTLOADER started it and ESP_DEPLOYMENTS deployments fit; both
# reports print even when the first fails.
check_boot() {
	local status=0
	vm "set -euo pipefail; $(declare -f report_bootloader); report_bootloader $(printf %q "${EXPECT_BOOTLOADER}")" || status=1
	vm "set -euo pipefail; $(declare -f report_esp); report_esp ${ESP_DEPLOYMENTS}" || status=1
	return "${status}"
}

# Waits up to BOOT_WAIT_SECS for SSH to answer with a boot ID other than
# $1 (empty: any boot).
wait_for_boot() {
	local old_boot=$1 new_boot remaining deadline=$((SECONDS + BOOT_WAIT_SECS))
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
