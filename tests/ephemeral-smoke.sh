#!/usr/bin/bash
# Runs inside a `bcvk ephemeral` VM; `just ephemeral-smoke` passes it in
# base64 so no quoting survives several shells. Expects EXPECT_IMAGE_NAME,
# EXPECT_TAG and EXPECT_VARIANT.

set -euo pipefail

: "${EXPECT_IMAGE_NAME:?}" "${EXPECT_TAG:?}" "${EXPECT_VARIANT:?}"
info=/usr/share/ublue-os/image-info.json

for _ in $(seq 1 60); do
    systemctl is-active --quiet NetworkManager && break
    sleep 2
done
systemctl is-active NetworkManager
test "$(jq -r '."image-name"' "${info}")" = "${EXPECT_IMAGE_NAME}"
test "$(jq -r '."image-tag"' "${info}")" = "${EXPECT_TAG}"
bootc status
case "${EXPECT_VARIANT}" in
server) test "$(systemctl get-default)" = multi-user.target ;;
desktop) test "$(systemctl get-default)" = graphical.target ;;
*) echo "error: unknown EXPECT_VARIANT '${EXPECT_VARIANT}'" >&2; exit 1 ;;
esac
command -v tmux gum k3s
test "$(systemctl is-enabled k3s.service || true)" = disabled
systemctl is-active firewalld
test "$(systemctl is-enabled cockpit.socket || true)" = disabled
for unit in cockpit.socket cockpit.service; do
    test "$(systemctl is-active "${unit}" || true)" = inactive
done
test -z "$(ss -H -lnt 'sport = :9090')"
getent hosts fedoraproject.org
# Any HTTP response proves DNS, routing and TLS; not --fail, since one of
# fedoraproject.org's proxies intermittently answers 404.
curl --silent --show-error --head https://fedoraproject.org >/dev/null
echo "ephemeral smoke passed"
