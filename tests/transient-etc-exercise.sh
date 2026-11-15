#!/usr/bin/bash
# Run inside a transient-/etc VM by transient-etc-vm-test.sh: exercise
# common services so their writes to /etc show up in the report. A failed
# step is a finding, not a test failure: it prints a Markdown list of steps
# and their results on stdout and the commands' output on stderr.
# Usage: transient-etc-exercise.sh [BUDGET_SECS]. All steps share the budget
# (default 780), so the script ends in the VM before the caller's SSH timeout
# rather than running on after a killed connection.

set -uo pipefail

readonly CONNECTION=atomic-linux-transient-etc-test
readonly PODMAN_IMAGE=quay.io/libpod/alpine:latest
readonly STEP_TIMEOUT_SECS=600
readonly POLL_TIMEOUT_SECS=30
# Overridable so synthetic tests never run a host's validator.
readonly K3S_VALIDATE="${K3S_VALIDATE:-/usr/libexec/k3s-validate}"
readonly DEADLINE=$((SECONDS + 10#${1:-780}))

# Sets limit: the step timeout, cut to what is left of the budget.
step_limit() {
	limit=$((DEADLINE - SECONDS))
	((limit < STEP_TIMEOUT_SECS)) || limit=${STEP_TIMEOUT_SECS}
	((limit > 0))
}

report() {
	local desc=$1 status=$2
	if ((status == 0)); then
		printf -- '- ok: %s\n' "${desc}"
	else
		printf -- '- **failed** (exit %s): %s\n' "${status}" "${desc}"
	fi
}

# Run a command under the step timeout.
step() {
	local desc=$1 limit status=0
	shift
	if ! step_limit; then
		printf -- '- **skipped** (exercise budget exhausted): %s\n' "${desc}"
		return
	fi
	timeout --kill-after=5s "${limit}" "$@" >&2 || status=$?
	report "${desc}" "${status}"
}

# Poll a command until it succeeds or the step timeout passes; one poll
# gets at most POLL_TIMEOUT_SECS, so a hung call cannot outlast the budget.
wait_step() {
	local desc=$1 limit deadline status=0
	shift
	if ! step_limit; then
		printf -- '- **skipped** (exercise budget exhausted): %s\n' "${desc}"
		return
	fi
	deadline=$((SECONDS + limit))
	until timeout --kill-after=5s "${POLL_TIMEOUT_SECS}" "$@" >&2; do
		if ((SECONDS >= deadline)); then
			status=1
			break
		fi
		sleep 5
	done
	report "${desc}" "${status}"
}

# One unit per call: is-active succeeds if any of several units is active.
wait_step 'graphical.target reached' systemctl is-active --quiet graphical.target
wait_step 'gdm active' systemctl is-active --quiet gdm.service
step 'NetworkManager: add a connection' nmcli connection add type dummy ifname atltest0 con-name "${CONNECTION}" \
	ipv4.method manual ipv4.addresses 192.0.2.1/24
step 'NetworkManager: remove it' nmcli connection delete "${CONNECTION}"
step 'firewalld: runtime port change' firewall-cmd --add-port=8080/tcp
step 'firewalld: revert it' firewall-cmd --remove-port=8080/tcp
step "podman run ${PODMAN_IMAGE}" podman run --rm "${PODMAN_IMAGE}" true
step 'timedatectl set-timezone' timedatectl set-timezone America/New_York
step 'hostnamectl set-hostname' hostnamectl set-hostname atomic-linux-transient-etc
step 'k3s: enable, through k3s-preflight' systemctl enable --now k3s.service
step 'k3s: k3s-validate passes' "${K3S_VALIDATE}"
step 'system running, no failed units' systemctl is-system-running --wait
timeout --kill-after=5s 30 systemctl --failed --no-legend --plain | awk '{ print "  - failed unit: " $1 }' || true
