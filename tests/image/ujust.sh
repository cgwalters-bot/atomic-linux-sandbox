#!/usr/bin/bash
# Validate the installed entry point and assembled drop-ins without host mutations.
set -euo pipefail

ujust --list
recipes=$(ujust --summary)
for recipe in status upgrade rollback reboot update-and-reboot clean-containers clean-container-volumes; do
	if [[ " ${recipes} " != *" ${recipe} "* ]]; then
		echo "error: missing host recipe: ${recipe}" >&2
		exit 1
	fi

	# Resolves each recipe through the installed ujust entry point without running it.
	ujust --dry-run "${recipe}"
done

for recipe in benchmark configure-dev-groups toggle-example-feature; do
	if [[ " ${recipes} " == *" ${recipe} "* ]]; then
		echo "error: placeholder recipe still installed: ${recipe}" >&2
		exit 1
	fi
done

for tool in bootc sudo systemctl podman gum; do
	command -v "${tool}"
done

# The mocks below accept any flags, so check the real tools accept the recipes'.
# Podman rejects an unknown flag before printing help.
for subcommand in 'container prune' 'network prune' 'image prune --all' 'volume prune'; do
	# shellcheck disable=SC2086
	podman --remote=false ${subcommand} --help >/dev/null
done
gum_help=$(gum confirm --help)
for flag in --timeout --default; do
	if [[ "${gum_help}" != *"${flag}"* ]]; then
		echo "error: gum confirm does not accept ${flag}" >&2
		exit 1
	fi
done

# Intercept every privileged/destructive command; never operate on container state.
mock_dir=$(mktemp -d)
trap 'rm -rf "${mock_dir}"' EXIT
export CALL_LOG="${mock_dir}/calls"
for tool in sudo bootc gum systemctl podman; do
	# Expand mock variables when the generated script runs, not while writing it.
	# shellcheck disable=SC2016
	printf '%s\n' '#!/usr/bin/bash' \
		'echo "${0##*/} $*" >> "$CALL_LOG"' \
		'case "${0##*/}" in' \
		'  sudo) exec "$@";;' \
		'  bootc) exit "${UPGRADE_STATUS:-0}";;' \
		'  gum) exit "${CONFIRM_STATUS:-1}";;' \
		'  podman) [[ ! -v CONTAINER_HOST && ! -v CONTAINER_CONNECTION ]];;' \
		'esac' >"${mock_dir}/${tool}"
	chmod +x "${mock_dir}/${tool}"
done
export PATH="${mock_dir}:${PATH}"

assert_calls() {
	local actual
	actual=$(<"${CALL_LOG}")
	if [[ "${actual}" != "$1" ]]; then
		printf 'error: unexpected host calls:\n%s\n' "${actual}" >&2
		exit 1
	fi
}

: >"${CALL_LOG}"
ujust status
assert_calls $'sudo bootc status\nbootc status'

: >"${CALL_LOG}"
if UPGRADE_STATUS=1 ujust update-and-reboot; then
	echo 'error: failed upgrade reported success' >&2
	exit 1
fi
assert_calls $'sudo bootc upgrade\nbootc upgrade'

: >"${CALL_LOG}"
ujust reboot
assert_calls 'gum confirm --timeout=0s --default=false Reboot the host now?'

: >"${CALL_LOG}"
CONFIRM_STATUS=0 ujust reboot
assert_calls $'gum confirm --timeout=0s --default=false Reboot the host now?\nsystemctl reboot'

: >"${CALL_LOG}"
ujust update-and-reboot
assert_calls $'sudo bootc upgrade\nbootc upgrade\ngum confirm --timeout=0s --default=false Reboot the host now?'

: >"${CALL_LOG}"
CONFIRM_STATUS=0 ujust update-and-reboot
assert_calls $'sudo bootc upgrade\nbootc upgrade\ngum confirm --timeout=0s --default=false Reboot the host now?\nsystemctl reboot'

: >"${CALL_LOG}"
export CONTAINER_HOST=unix:///nonexistent CONTAINER_CONNECTION=not-local
ujust clean-container-volumes
assert_calls "gum confirm --timeout=0s --default=false Permanently delete this user's unused Podman volumes and their data?"

: >"${CALL_LOG}"
ujust clean-containers
assert_calls $'podman --remote=false container prune\npodman --remote=false network prune\npodman --remote=false image prune --all'

: >"${CALL_LOG}"
CONFIRM_STATUS=0 ujust clean-container-volumes
assert_calls $'gum confirm --timeout=0s --default=false Permanently delete this user\'s unused Podman volumes and their data?\npodman --remote=false volume prune'
