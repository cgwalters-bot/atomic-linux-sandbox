#!/usr/bin/bash
# Isolated dconf round-trip, not an actual idle/suspend GNOME session test.
set -euo pipefail
[[ "${VARIANT:?}" == desktop ]] || exit 0
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
export DCONF_PROFILE="${tmp}/profile" XDG_CONFIG_HOME="${tmp}/config"
mkdir "${tmp}/db.d"
printf 'user-db:user\nfile-db:%s/db\n' "${tmp}" >"${DCONF_PROFILE}"
schema=org.gnome.settings-daemon.plugins.power
read_settings() {
	for power in ac battery; do
		gsettings get "${schema}" "sleep-inactive-${power}-type"
	done
}
dconf compile "${tmp}/db" "${tmp}/db.d"
baseline=$(read_settings)
# The example is deliberately outside system/ and must never be activated.
test ! -e /etc/dconf/db/local.d/60-no-auto-suspend
test ! -e /etc/dconf/db/gdm.d/60-no-auto-suspend
cp /ctx/custom/variants/desktop/no-auto-suspend.dconf "${tmp}/db.d/60-no-auto-suspend"
dconf compile "${tmp}/db" "${tmp}/db.d"
test "$(read_settings)" = "$(printf "'nothing'\n'nothing'")"
rm "${tmp}/db.d/60-no-auto-suspend"
dconf compile "${tmp}/db" "${tmp}/db.d"
test "$(read_settings)" = "${baseline}"
