#!/usr/bin/bash
# The default firewalld zone denies everything inbound apart from ssh and
# tailscale: no other services, ports, protocols or rich rules.
set -euo pipefail

zone=$(firewall-offline-cmd --get-default-zone)
services=$(firewall-offline-cmd --zone="${zone}" --list-services | tr ' ' '\n' | sort | xargs)
if [[ "${services}" != "ssh tailscale" ]]; then
	echo "error: zone ${zone} allows services '${services}', expected 'ssh tailscale'" >&2
	exit 1
fi

for list in ports protocols source-ports forward-ports rich-rules sources interfaces; do
	entries=$(firewall-offline-cmd --zone="${zone}" "--list-${list}")
	if [[ -n "${entries}" ]]; then
		echo "error: zone ${zone} has ${list}: ${entries}" >&2
		exit 1
	fi
done

for query in masquerade icmp-block-inversion; do
	if firewall-offline-cmd --zone="${zone}" "--query-${query}" >/dev/null; then
		echo "error: zone ${zone} has ${query} enabled" >&2
		exit 1
	fi
done

target=$(firewall-offline-cmd --zone="${zone}" --get-target)
if [[ "${target}" != default ]]; then
	echo "error: zone ${zone} target is '${target}', expected 'default'" >&2
	exit 1
fi

ports=$(firewall-offline-cmd --service=tailscale --get-ports)
if [[ "${ports}" != 41641/udp ]]; then
	echo "error: tailscale service ports are '${ports}', expected 41641/udp" >&2
	exit 1
fi
