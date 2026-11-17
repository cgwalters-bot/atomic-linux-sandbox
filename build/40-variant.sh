#!/usr/bin/bash
# Add a variant on top of the shared base: the drop-ins under
# custom/variants/VARIANT (see drop-ins.sh) and its default target.
#   server   headless; nothing beyond the base
#   desktop  GNOME, booting to GDM

set -euo pipefail

# shellcheck source=build/drop-ins.sh
source /ctx/build/drop-ins.sh

# shellcheck source=build/ttm-kargs.sh
source /ctx/build/ttm-kargs.sh

VARIANT="${VARIANT:-desktop}"

case "${VARIANT}" in
server) target=multi-user.target ;;
desktop) target=graphical.target ;;
*)
	echo "error: unknown VARIANT '${VARIANT}' (expected server or desktop)" >&2
	exit 1
	;;
esac

apply_drop_ins "/ctx/custom/variants/${VARIANT}"
write_ttm_kargs ""
systemctl set-default "${target}"
