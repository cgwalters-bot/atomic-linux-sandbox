# atomic-linux: a generic Fedora bootc host image, as a shared headless base
# plus a server and a desktop variant (ARG VARIANT).
#
# It is meant to be derived from, not edited: a downstream repository holds
# a small Containerfile starting with
#   FROM ghcr.io/cgwalters-forge/atomic-linux@sha256:...
# plus its own configuration. See README.md.
#
# The build follows the Universal Blue finpilot template's multi-stage layout
# (https://github.com/projectbluefin/finpilot): a scratch "ctx" stage gathers
# local build scripts and files plus OCI context images, and RUN steps bind
# mount it at /ctx.

# OCI context images, pinned by digest (Dependabot proposes bumps).
FROM ghcr.io/projectbluefin/common:latest@sha256:8d11dd33fe3dfa6c960c0543e6b309a5a2517b7a6fef438647ae53a5f500f7ec AS common
FROM ghcr.io/ublue-os/brew:latest@sha256:c201bc801e4828849e8e36c4adcb5c0f38d35ac3ff9546a0ecab0fd2beabf51f AS brew

FROM scratch AS ctx
COPY build /build
COPY custom /custom
# @projectbluefin/common is carried in the context for scripts that want
# Bluefin's shared desktop files; 10-build.sh does not overlay it today.
COPY --from=common /system_files /oci/common
COPY --from=brew /system_files /oci/brew

# The shared base: headless Fedora bootc, with what every variant carries.
# Alternative with the same layout: quay.io/centos-bootc/centos-bootc:stream10.
FROM quay.io/fedora/fedora-bootc:45@sha256:d3f0430d6a5f0df81eaebda4d4a4ea3c3fe2524dfbc135059e7811d35902309d AS base

# The build's own tools (dnf5 config-manager and versionlock, rsync). Keep the
# dnf cache during the build; clean-stage.sh restores the default.
RUN --mount=type=cache,dst=/var/cache/libdnf5 \
    dnf5 install -y dnf5-plugins rsync \
    && cp /etc/dnf/dnf.conf /etc/dnf/dnf.conf.tmp \
    && mv /etc/dnf/dnf.conf.tmp /etc/dnf/dnf.conf \
    && dnf5 config-manager setopt keepcache=1 install_weak_deps=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/10-build.sh

# Optional: a newer bootc, the composefs storage backend instead of ostree,
# and a transient /etc; see build/15-bootc.sh and the README. The defaults
# change nothing.
ARG BOOTC_SOURCE="fedora"
ARG STORAGE_BACKEND="ostree"
ARG ETC_MODE="persistent"
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    BOOTC_SOURCE="${BOOTC_SOURCE}" STORAGE_BACKEND="${STORAGE_BACKEND}" ETC_MODE="${ETC_MODE}" /ctx/build/15-bootc.sh

# k3s is a separately pinned release, installed but not enabled; a derived
# image opts in with `systemctl enable k3s.service`.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/20-k3s.sh

# The published image: the base plus one variant, server (headless) or
# desktop (GNOME); see build/40-variant.sh.
FROM base

ARG VARIANT="desktop"
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT="${VARIANT}" bash /ctx/build/40-variant.sh

# Image identity, recorded in /usr/share/ublue-os/image-info.json. Derived
# images re-run /usr/libexec/atomic-linux/write-image-info with their own.
# It comes after the base so that the base depends on neither tag nor variant.
ARG IMAGE_NAME="atomic-linux"
ARG IMAGE_VENDOR="cgwalters-forge"
ARG IMAGE_REGISTRY="ghcr.io/cgwalters-forge"
ARG UBLUE_IMAGE_TAG="stable"
ARG BASE_IMAGE_NAME="fedora-bootc"
ARG FEDORA_MAJOR_VERSION="45"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    install -D -m 0755 /ctx/build/00-image-info.sh /usr/libexec/atomic-linux/write-image-info \
    && /usr/libexec/atomic-linux/write-image-info

# /run is deliberately not a tmpfs here: clean-stage.sh must remove
# image-layer files such as /run/dnf so bootc lint's nonempty-run-tmp check
# passes.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=tmpfs,dst=/boot \
    /ctx/build/clean-stage.sh

# Writable /opt for runtime-installed software. An image that installs RPMs
# into /opt at build time should use `RUN rm /opt && mkdir /opt` instead.
RUN rm -rf /opt && ln -s /var/opt /opt

CMD ["/sbin/init"]

RUN bootc container lint --fatal-warnings
