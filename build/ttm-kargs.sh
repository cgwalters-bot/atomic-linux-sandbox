#!/usr/bin/bash
# Sourced at build time. Validate before writing so malformed build input
# cannot inject additional kernel arguments or TOML syntax.
write_ttm_kargs() {
	local root=$1 name value
	local -a kargs=()
	for name in TTM_PAGES_LIMIT TTM_PAGE_POOL_SIZE; do
		value=${!name:-}
		[[ -n "${value}" ]] || continue
		# Canonical decimal page counts, bounded to a signed 32-bit integer.
		# Check length before arithmetic to avoid overflow on hostile input.
		if [[ ! "${value}" =~ ^(0|[1-9][0-9]{0,9})$ ]] || ((value > 2147483647)); then
			printf 'error: %s must be a decimal page count from 0 to 2147483647\n' "${name}" >&2
			return 1
		fi
		case "${name}" in
		TTM_PAGES_LIMIT) kargs+=("ttm.pages_limit=${value}") ;;
		TTM_PAGE_POOL_SIZE) kargs+=("ttm.page_pool_size=${value}") ;;
		esac
	done
	# No file (or even directory) in the default build.
	((${#kargs[@]})) || return 0
	install -d "${root}/usr/lib/bootc/kargs.d"
	{
		printf 'kargs = [\n'
		printf '  "%s",\n' "${kargs[@]}"
		printf ']\n'
	} >"${root}/usr/lib/bootc/kargs.d/60-ttm.toml"
}
