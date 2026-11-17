#!/usr/bin/bash
# Match the same optional inputs used to build this tag.
set -euo pipefail
# shellcheck source=build/ttm-kargs.sh
source /ctx/build/ttm-kargs.sh
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
write_ttm_kargs "${tmp}"
file=usr/lib/bootc/kargs.d/60-ttm.toml
if [[ -f "${tmp}/${file}" ]]; then
	cmp "${tmp}/${file}" "/${file}"
else
	test ! -e "/${file}"
fi
