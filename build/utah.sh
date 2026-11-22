#!/usr/bin/bash
# Add atomic-linux's host pieces to Utah (Containerfile.utah): k3s and its
# configuration, the firewalld zones, the install configuration, key-only
# sshd (enabled, since bcvk's VM install waits for SSH) and the
# composefs-native setup. Utah's desktop, Flatpaks and update policy stay as
# they are, and so does its bootc.

set -euo pipefail

# The parts of custom/system this variant takes. Cockpit, restic,
# runner.slice, registries.conf, the presets and the update drop-in stay with
# the default image.
readonly SYSTEM_PATHS=(
	etc/firewalld
	etc/rancher
	etc/ssh/sshd_config.d
	usr/lib/bootc/install
	usr/lib/k3s-host
	usr/lib/systemd/system/k3s-preflight.service
	usr/lib/systemd/system/k3s.service
	usr/libexec/k3s-preflight
	usr/libexec/k3s-validate
)

echo "::group:: atomic-linux files for Utah"
for path in "${SYSTEM_PATHS[@]}"; do
	rsync -rvK --relative "/ctx/custom/system/./${path}" /
done
# Utah's presets disable sshd as a desktop default.
systemctl enable sshd.service
echo "::endgroup::"

# fedora keeps the base image's bootc, here Utah's (1.17.4 when this was
# written), which lacks the fork's to-existing-root fixes.
BOOTC_SOURCE=fedora /ctx/build/15-bootc.sh

# Also enables firewalld with our locked-down FedoraWorkstation zone as the
# default, replacing Utah's lax zone.
/ctx/build/20-k3s.sh
