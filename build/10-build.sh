#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Main Build Script
###############################################################################
# This script follows the @ublue-os/bluefin pattern for build scripts.
# It uses set -euo pipefail for strict error handling.
# It builds the shared base; 40-variant.sh adds a variant on top.
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh
# shellcheck source=build/drop-ins.sh
source /ctx/build/drop-ins.sh

echo "::group:: Overlay Brew Integration Files"

# Brew integration files from @ublue-os/brew OCI (tarball, systemd services, shell integration)
rsync -rvK /ctx/oci/brew/ /

echo "::endgroup::"

# custom/packages/*.txt, custom/system/ and custom/units/*.enable.
apply_drop_ins /ctx/custom

# Also remove any enablement inherited from the base, not just RPM presets.
systemctl disable cockpit.socket

# Example using COPR with isolated pattern:
# copr_install_isolated "ublue-os/staging" package-name

# Example: systemctl mask unwanted-service

echo "::group:: Copy User-Facing Files"

# Enable nullglob for all glob operations to prevent failures on empty matches
shopt -s nullglob

# Copy Brewfiles to standard location
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Consolidate Just Files
mkdir -p /usr/share/ublue-os/just/
find /ctx/custom/ujust -iname '*.just' -exec printf "\n\n" \; -exec cat {} \; >>/usr/share/ublue-os/just/60-custom.just

# Copy Flatpak preinstall files
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

# Restore default glob behavior
shopt -u nullglob

echo "::endgroup::"

echo "Custom build complete!"
