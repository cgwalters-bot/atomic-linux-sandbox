#!/usr/bin/bash
# Make the image composefs-native, optionally with a newer bootc.
#
# The image ships /usr/lib/composefs/setup-root-conf.toml and no ostree
# prepare-root.conf, which is how bootc install recognizes a composefs-native
# image (bootc-setup-root-conf.toml(5)), and its initramfs carries bootc's
# 51bootc dracut module, which mounts the composefs root.
#
# BOOTC_SOURCE selects where bootc comes from:
#   fedora           the base image's bootc, unchanged (the default)
#   updates-testing  the newest Fedora build, from updates-testing
#   copr             bootc's upstream main branch, from the rhcontainerbot/bootc
#                    COPR (Packit builds of every merge)
#
# ETC_MODE selects how /etc is mounted at boot:
#   persistent  the default
#   transient   setup-root-conf.toml's [etc] transient: /etc is an overlay with
#               its upper on a tmpfs, so nothing written to /etc survives a
#               reboot. A test variant (README, "transient /etc"): it also gets
#               custom/transient-etc, which turns on audit from boot and
#               watches writes to /etc, for tests/transient-etc-vm-test.sh to
#               attribute them.

set -euo pipefail
# Also inside $(regenerate_initramfs), so a failed dracut stops the build.
shopt -s inherit_errexit

readonly BOOTC_COPR="rhcontainerbot/bootc"
readonly DRACUT_CONF=/usr/lib/dracut/dracut.conf.d/50-atomic-linux-bootc.conf
readonly SETUP_ROOT_CONF=/usr/lib/composefs/setup-root-conf.toml
# bootc 1.17.0 declared the backend stable, and older releases neither pick
# composefs from setup-root-conf.toml nor pass bootc container lint without
# ostree's prepare-root.conf.
readonly COMPOSEFS_MIN_BOOTC="1.17"

BOOTC_SOURCE="${BOOTC_SOURCE:-fedora}"
ETC_MODE="${ETC_MODE:-persistent}"

case "${ETC_MODE}" in
persistent | transient) ;;
*)
	echo "error: unknown ETC_MODE '${ETC_MODE}' (expected persistent or transient)" >&2
	exit 1
	;;
esac

# Rebuild the one kernel's initramfs from the image's /usr and print its path.
regenerate_initramfs() {
	local kernels kver
	# Exactly one kernel is expected in a bootc image.
	shopt -s nullglob
	kernels=(/usr/lib/modules/*/vmlinuz)
	shopt -u nullglob
	if ((${#kernels[@]} != 1)); then
		echo "error: expected one kernel in /usr/lib/modules, found ${#kernels[@]}" >&2
		exit 1
	fi
	kver=$(basename "$(dirname "${kernels[0]}")")
	# dracut copies /root, a symlink to var/roothome that the image's /var does
	# not carry; clean-stage.sh removes this again. The base image's
	# dracut.conf.d already sets hostonly=no.
	mkdir -p /var/roothome
	DRACUT_NO_XATTR=1 dracut --force --reproducible --kver "${kver}" "/usr/lib/modules/${kver}/initramfs.img" >&2
	echo "/usr/lib/modules/${kver}/initramfs.img"
}

echo "::group:: bootc from ${BOOTC_SOURCE}"
case "${BOOTC_SOURCE}" in
fedora) ;;
updates-testing)
	dnf5 -y upgrade --enablerepo=updates-testing bootc
	;;
copr)
	# Upgrade, not install: the COPR's git-snapshot versions sort above
	# Fedora's releases, and the base image's bootc is already installed.
	dnf5 -y copr enable "${BOOTC_COPR}"
	dnf5 -y copr disable "${BOOTC_COPR}"
	dnf5 -y upgrade --enablerepo="copr:copr.fedorainfracloud.org:${BOOTC_COPR//\//:}" bootc
	;;
*)
	echo "error: unknown BOOTC_SOURCE '${BOOTC_SOURCE}' (expected fedora, updates-testing or copr)" >&2
	exit 1
	;;
esac
rpm -q bootc
bootc_version=$(bootc --version | awk '{print $2}')
if [[ "$(printf '%s\n' "${COMPOSEFS_MIN_BOOTC}" "${bootc_version}" | sort -V | head -n1)" != "${COMPOSEFS_MIN_BOOTC}" ]]; then
	echo "error: composefs needs bootc ${COMPOSEFS_MIN_BOOTC} or newer, found ${bootc_version}; set BOOTC_SOURCE=updates-testing or copr" >&2
	exit 1
fi
echo "::endgroup::"

echo "::group:: composefs-native image (/etc ${ETC_MODE})"
mkdir -p "$(dirname "${SETUP_ROOT_CONF}")"
if [[ "${ETC_MODE}" == transient ]]; then
	printf '[etc]\ntransient = true\n' >"${SETUP_ROOT_CONF}"
	# The boot arguments and audit watch that the VM test's report needs.
	rsync -rvK --chmod=D0755,F0644 /ctx/custom/transient-etc/ /
	systemctl enable atomic-linux-etc-watch.service
else
	# An empty file is valid and means the defaults.
	: >"${SETUP_ROOT_CONF}"
fi
chmod 0644 "${SETUP_ROOT_CONF}"
rm -f /usr/lib/ostree/prepare-root.conf /etc/ostree/prepare-root.conf

printf '# Mount the composefs root in the initramfs (bootc-root-setup.service(5)).\nadd_dracutmodules+=" bootc "\n' >"${DRACUT_CONF}"

initramfs=$(regenerate_initramfs)
# Not grep -q: with pipefail, lsinitrd would die of SIGPIPE.
if ! lsinitrd "${initramfs}" | grep 'usr/lib/bootc/initramfs-setup' >/dev/null; then
	echo "error: the regenerated initramfs lacks bootc's initramfs-setup" >&2
	exit 1
fi
# 51bootc copies setup-root-conf.toml into the initramfs, where
# bootc-root-setup.service reads it.
if ! lsinitrd -f "${SETUP_ROOT_CONF#/}" "${initramfs}" | cmp -s - "${SETUP_ROOT_CONF}"; then
	echo "error: the regenerated initramfs's ${SETUP_ROOT_CONF} differs from the image's" >&2
	exit 1
fi
echo "::endgroup::"
