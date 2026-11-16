#!/usr/bin/bash
# The effective sshd configuration allows key login only. The image ships no
# host keys, so generate a throwaway one for `sshd -T`.
set -euo pipefail

keydir=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -f "${keydir}/host_key"
config=$(sshd -T -h "${keydir}/host_key")
for expected in 'passwordauthentication no' 'kbdinteractiveauthentication no' \
	'permitrootlogin prohibit-password' 'pubkeyauthentication yes'; do
	# Fedora 45's OpenSSH prints keywords in mixed case, older ones lowercase.
	if ! grep -qixF "${expected}" <<<"${config}"; then
		echo "error: sshd -T lacks '${expected}'" >&2
		exit 1
	fi
done
