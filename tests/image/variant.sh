#!/usr/bin/bash
# The image is the VARIANT `just image-test` passes: its drop-ins under
# custom/variants are applied, it boots to the variant's target, and the
# server stays headless.
set -euo pipefail
shopt -s nullglob

: "${VARIANT:?VARIANT must be set}"

entries() {
	sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$@"
}

dir="/ctx/custom/variants/${VARIANT}"
case "${VARIANT}" in
server) expected_target=multi-user.target ;;
desktop) expected_target=graphical.target ;;
*)
	echo "error: unknown VARIANT '${VARIANT}'" >&2
	exit 1
	;;
esac

target=$(systemctl get-default)
if [[ "${target}" != "${expected_target}" ]]; then
	echo "error: default target is ${target}, expected ${expected_target}" >&2
	exit 1
fi

package_files=("${dir}"/packages/*.txt)
if ((${#package_files[@]})); then
	mapfile -t packages < <(entries "${package_files[@]}")
	rpm -q "${packages[@]}"
fi

unit_files=("${dir}"/units/*.enable)
if ((${#unit_files[@]})); then
	mapfile -t units < <(entries "${unit_files[@]}")
	for unit in "${units[@]}"; do
		state=$(systemctl is-enabled "${unit}" || true)
		if [[ "${state}" != enabled ]]; then
			echo "error: ${unit} is '${state}', expected enabled" >&2
			exit 1
		fi
	done
fi

# The server is headless: nothing of the desktop's session leaks into it.
if [[ "${VARIANT}" == server ]]; then
	for package in gdm gnome-shell; do
		if rpm -q "${package}" >/dev/null; then
			echo "error: the server variant has ${package} installed" >&2
			exit 1
		fi
	done
fi

# Desktops upgrading from Silverblue keep their Flatpak apps, Wi-Fi, audio
# and keyring, whatever the drop-in lists say.
if [[ "${VARIANT}" == desktop ]]; then
	rpm -q flatpak NetworkManager-wifi wpa_supplicant pipewire wireplumber gnome-keyring power-profiles-daemon toolbox fwupd mesa-vulkan-drivers vulkan-loader
	command -v flatpak >/dev/null
	# Validate the installed RADV manifest and its actual ELF library, not
	# just the package name (which also contains software Vulkan drivers).
	mapfile -t icds < <(rpm -ql mesa-vulkan-drivers | grep '/radeon_icd.*\.json$')
	((${#icds[@]} > 0))
	for icd in "${icds[@]}"; do
		library=$(jq -er '.ICD.library_path | select(contains("libvulkan_radeon.so"))' "${icd}")
		if [[ "${library}" == /* ]]; then
			test -f "${library}"
		else
			ldconfig -p | grep -F "${library} "
		fi
	done
fi
