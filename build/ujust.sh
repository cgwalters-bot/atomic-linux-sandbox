#!/usr/bin/bash
# Use only this image's assembled recipes, not a Justfile in the caller's cwd.
set -euo pipefail
if (($# == 0)); then set -- --list; fi
exec just --justfile /usr/share/ublue-os/just/60-custom.just "$@"
