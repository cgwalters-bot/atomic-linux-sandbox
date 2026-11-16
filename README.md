> This text is LLM generated.

# atomic-linux

A generic [bootc](https://bootc-dev.github.io/) desktop and host image built
on Fedora Silverblue, published as `ghcr.io/cgwalters-forge/atomic-linux`.
It is a base to derive from, not a finished personal system: what is specific
to one machine or person (users, SSH keys, network and VPN setup, hardware
tuning, extra packages) belongs in a small downstream image that starts
`FROM` this one.

It started as a [Universal Blue finpilot](https://github.com/projectbluefin/finpilot)
image and keeps finpilot's multi-stage layout and examples. Status: early.
The image builds and passes `bootc container lint`, and CI boots each
build of it with `just ephemeral-smoke` and the k3s VM check. The KubeVirt test passed on the
predecessor image but has not been rerun here, nothing has run on hardware,
and images are not yet signed.

## What is in the image

- Fedora Silverblue 44 (GNOME), digest-pinned, with Universal Blue's
  Homebrew integration (`brew-setup`, update and upgrade timers), `ujust`
  example recipes, and example Brewfiles and Flatpak preinstall files.
  `@projectbluefin/common` is in the build context but not overlaid.
- `tmux` and `gum` (used by the ujust recipes); `podman.socket` enabled.
- Host services: `tailscaled` enabled but not logged in (`tailscale up`, tags
  and keys are left to the machine's owner), toolbox, chronyd, and `git`,
  `just`, `jq` and `curl`. No Node.js. `restic-backup.timer` runs a daily
  `restic backup` once both `/etc/restic-backup/env` (an `EnvironmentFile`
  with `RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE` and any backend
  credentials) and `/etc/restic-backup/paths` (one path per line) exist;
  until then it does nothing. It uses `--one-file-system`, so list each
  mount or btrfs subvolume, and `/var/home` rather than the `/home` symlink.
  Pruning old snapshots is left to the owner.
- Debug tools for hosts that cannot easily rebuild: `strace`, `ltrace`,
  `perf`, `bpftrace` and `sysstat`. sysstat's periodic collection into
  `/var/log/sa` is preset off; `systemctl enable sysstat.service` turns it on.
- `sshd.service` enabled, because bcvk's VM install waits for SSH. That is a
  real exposure, so firewalld governs it and sshd accepts keys only: password
  and keyboard-interactive login are off, and root may log in only with a key.
- Hardware support kept independent of the base's desktop package set
  (`custom/packages/hardware.txt`): linux-firmware plus its CPU microcode,
  GPU and NIC subpackages, NetworkManager with wifi, tpm2-tools,
  smartmontools (`smartd` enabled; it skips VMs) and fwupd.
  `fwupd-refresh.timer` is enabled, so every host periodically fetches LVFS
  metadata; it never applies firmware by itself.
- `bootc-fetch-apply-updates.timer` enabled, but stage-only: updates are
  fetched and staged in the background and never trigger a reboot
  ([docs/updates.md](docs/updates.md)).
- `bootc install` defaults to a btrfs root.
- Container short names are enforcing, with no search registries.
- firewalld enabled, and the default `FedoraWorkstation` zone denies
  everything inbound apart from `ssh` and `tailscale` (UDP 41641, for direct
  tailnet connections), replacing Fedora's 1025-65535 tcp/udp opening.
  `dhcpv6-client` and `samba-client` are gone too, so stateful DHCPv6 and
  NetBIOS browsing need a derived image to add them back.
- k3s, checksum-pinned with k3s-selinux, **installed but disabled**. Its
  configuration (SELinux, secrets encryption, Flannel VXLAN, Traefik and
  ServiceLB off, NodePorts on loopback only, a `k3s` firewalld zone trusting
  only the pod and service CIDRs) and a preflight unit that loads the kernel
  modules and sysctls k3s needs only when k3s is enabled, so a desktop that
  never runs k3s is unaffected. `/usr/libexec/k3s-validate` is a bounded
  acceptance check for test VMs.
- `runner.slice`, a memory- and CPU-capped slice for CI runners and job
  VMs, unused until a unit opts in; see
  [Runner slice](#runner-slice).
- An isolated bridge for CI job VMs with an nftables egress allowlist,
  inert until `/etc/atomic-linux/runner-network.conf` exists; see
  [docs/runner-network.md](docs/runner-network.md).

## Runner slice

`runner.slice` keeps CI runner workloads and their job VMs from starving the
host: a runaway job is throttled at `MemoryHigh=75%` of physical RAM and
OOM-killed inside the slice at `MemoryMax=85%`, rather than pushing sshd and
the other host services into the kernel's global OOM killer. `CPUWeight=50`,
half the default weight of its sibling slices, lowers its CPU share under
contention. Nothing runs in it until a unit opts in with
`Slice=runner.slice`, so a host without runners is unaffected.

The limits live in `/usr/lib/systemd/system/runner.slice.d/50-limits.conf`.
Override them with a later-sorting drop-in, in a derived image or on the
host, and check the result with `systemctl show runner.slice -p MemoryMax`:

```ini
# /etc/systemd/system/runner.slice.d/60-local.conf
[Slice]
MemoryHigh=24G
MemoryMax=28G
```

## Deriving an image

A downstream repository needs little more than this Containerfile:

```dockerfile
FROM ghcr.io/cgwalters-forge/atomic-linux@sha256:<digest>

ARG IMAGE_NAME=my-host
ARG IMAGE_VENDOR=me
ARG IMAGE_REGISTRY=registry.example.com/me
RUN /usr/libexec/atomic-linux/write-image-info

COPY system/ /
RUN dnf5 install -y <packages> && dnf5 clean all \
    && systemctl enable k3s.service

RUN bootc container lint --fatal-warnings
```

Pin the base by digest (take it from the build summary of the commit you
want, or `skopeo inspect docker://ghcr.io/cgwalters-forge/atomic-linux:stable`)
and bump it in its own pull request. Configuration hooks:

| Hook | For |
| --- | --- |
| `/usr/libexec/atomic-linux/write-image-info` | Record the derived image's name and update origin in `image-info.json` |
| `/etc/rancher/k3s/config.yaml.d/*.yaml` | k3s settings; use `kubelet-arg+:` to add kubelet reservations without replacing the base list |
| `/etc/default/k3s-preflight` | `K3S_PREFLIGHT_REQUIRE_KVM=1` on KubeVirt hosts |
| `/etc/systemd/system/runner.slice.d/*.conf` | Runner memory and CPU limits; see [Runner slice](#runner-slice) |
| `/etc/atomic-linux/runner-network.conf` | Job VM bridge address, resolvers and egress allowlist ([docs](docs/runner-network.md)) |
| `/etc/modules-load.d/`, `/etc/modprobe.d/` | Hardware modules and options, e.g. `kvm_intel nested=1` |
| `/etc/ssh/sshd_config.d/` | sshd settings; a file sorting before `40-atomic-linux.conf` overrides the key-only defaults |

A derived image that installs packages should run `dnf5 clean all` (or reuse
this repository's `build/clean-stage.sh` pattern) so its own
`bootc container lint` passes.

## composefs backend (optional)

bootc has two storage backends: ostree, the default here, and
[composefs](https://bootc-dev.github.io/bootc/bootc-composefs.7.html), which
bootc 1.17.0 declared stable. `just build-composefs` builds a
composefs-native variant as `atomic-linux:composefs`: `build/15-bootc.sh`
installs a newer bootc, ships `/usr/lib/composefs/setup-root-conf.toml`,
removes ostree's `prepare-root.conf` and adds bootc's `51bootc` dracut module
to the initramfs. `bootc install` (and so bcvk) then picks the composefs
backend by itself, with GRUB and BLS entries; no `--composefs-backend` flag is
needed. The root is a read-only, fs-verity-checked EROFS image, and `/etc` and
`/var` are per-deployment and shared state directories under `/sysroot/state`.

It needs bootc 1.17 or newer, which Fedora 44 has only in updates-testing so
far; the build fails early with older bootc. `source=copr` takes upstream's
main branch from the `rhcontainerbot/bootc` COPR instead:

```sh
just build-composefs                     # bootc from Fedora updates-testing
just build-composefs composefs copr      # bootc from upstream main
just composefs-vm-test                   # install, upgrade, switch, rollback
```

`composefs-vm-test` installs the build in a disposable libvirt VM on a btrfs
root and checks that the composefs backend is booted, that an `/etc` and a
`/var` edit survive `bootc upgrade`, and that `bootc switch` and
`bootc rollback` boot the expected images, with SELinux enforcing and the k3s
preflight unit working. CI builds and lints the variant on every pull
request and push to `main`, boots it with `bcvk ephemeral` and runs
`composefs-vm-test`, but does not publish it, and these jobs do not gate
`stable`.

Known gaps, as of bootc 1.17.1 (October 2026):

- There is no in-place move from ostree; install fresh. Do not
  `bootc switch` an ostree install to the composefs build.
- rpm-ostree, and so GNOME Software's OS updates, do not work; use
  `bootc upgrade` (`ujust update-and-reboot`). `bootc-fetch-apply-updates.timer` is
  conditioned on `/run/ostree-booted` and never runs
  ([bootc#2578](https://github.com/bootc-dev/bootc/issues/2578)).
- With no separate `/boot` partition, systemd's GPT auto-generator mounts the
  ESP on `/boot` while the BLS entries and GRUB configuration live in
  `/sysroot/boot`, so `bootloader-update.service` (bootupd) fails on every
  boot and the system shows as degraded. Upgrades and rollback are unaffected.
- Upstream tests ext4 and XFS; btrfs, this image's default, is expected to
  work and passed the VM test here.
- No boot counting, logically bound images or `bootc edit`; see bootc's
  [known issues](https://bootc-dev.github.io/bootc/bootc-composefs.7.html#known-issues).

A derived image inherits the backend. If it changes bootc, it must also
regenerate the initramfs, which carries bootc's mount code.

## Transient /etc (test variant, opt-in)

`just build-transient-etc` builds `atomic-linux:transient-etc` with ostree's
`etc.transient`: `/etc` is an overlay whose upperdir is on tmpfs, reset on
every boot. `ETC_MODE` defaults to `persistent`; the normal image and stable
promotion are unchanged. Transient mode refuses `STORAGE_BACKEND=composefs`,
which does not use ostree's `prepare-root.conf`. The build preserves the
base configuration, regenerates the initramfs with ostree's dracut module,
and verifies that its copy of `prepare-root.conf` enables transient mode.
`bootc container lint --fatal-warnings` remains mandatory.

With bcvk, libvirt and KVM, run `just transient-etc-vm-test`. This installs a
disposable VM, asserts a tmpfs-backed `/etc`, writes a marker, reboots and
asserts the marker disappeared. Unlike `bcvk ephemeral`, this actually
exercises ostree-prepare-root. Only this variant includes the early audit
watch, `audit=1` and an audit-rules drop-in. It is measurement instrumentation,
not a security enforcement boundary; the test intentionally changes `/etc`.

The exercised scope is GDM/graphical.target activation (not interactive
login), NetworkManager connection add/delete, a runtime firewalld port
change/revert, podman running a small remote image, timezone and hostname
changes, and enabling k3s through its existing preflight then running
`k3s-validate`. Each service step is bounded; failures remain visible findings.
The podman image is not pinned, so remote availability/content can affect
that exercise. No services are migrated in this phase.

`output/transient-etc-report.md` lists audit-observed operations, including
create-then-delete and rename endpoints absent from the final upperdir,
separately from the final upperdir inventory. Failed syscalls are attempts,
not successful writes; even a successful watched syscall can include an
unmodified operand. Upperdir-only paths, including parent copy-ups, are
unattributed. Relative dirfd paths remain unresolved, never matched by
basename. Writers show audit executable/comm/PID; service identity is unknown
unless recorded in the event as a unit or an unambiguous service cgroup.
No current PID lookup, parent-unit inference or executable-name mapping is
used. Standard syscall audit records often lack unit/cgroup evidence;
synthetic cgroup tests are not evidence of live service attribution.

The collector compares `SYSCALL items` with all `PATH` indexes (including
PARENT and null-name records). Partially missing rename/multi-path events,
duplicates and malformed item metadata are reported with event IDs and
expected/received items, rather than silently appearing complete. Acceptance
requires the early watch to be active/exited with a successful result, zero
exit status, a satisfied condition and a nonzero activation timestamp; a
working late watch alone cannot hide a failed/skipped early unit.
The report exposes audit lost/backlog counters and describes initramfs,
rule-reload and nested-mount gaps. It is not a complete census. A missing
watch, missing audit probe, or failed collector fails acceptance.

Diagnostics (install/exercise/collector logs, journal for both boots, raw
audit log and VM state) are collected best effort before cleanup beside the
report in `output/transient-etc-report-diagnostics/`, even after failure.
`KEEP_FAILED_VM=1` retains a failed VM. Reports identify candidates to move
to `/usr` or declarative configuration before considering a default change.

An unreachable guest, stuck SSH client or blocked libvirt operation must not
hang this test's failure path. Host-side `timeout` bounds each call and kills
clients still running two seconds after TERM. Positive integer second budgets
are `VM_CALL_TIMEOUT=120`, `INSTALL_TIMEOUT_SECS=1800`,
`EXERCISE_TIMEOUT_SECS=900`, `DIAGNOSTIC_TIMEOUT_SECS=30` (per diagnostic),
`CLEANUP_TIMEOUT_SECS=60` and `BOOT_WAIT_SECS=300`. Reboot polls use the
remaining reboot budget. These are test deadlines, not image security controls.
Diagnostics remain best effort; failed cleanup fails an otherwise successful
test but never replaces the original failure status. Final acceptance is
reported only after cleanup. Killing an install/client may leave guest-side
work or a VM behind; cleanup is attempted even after a failed install, and
cleanup failures are reported rather than claimed as removal.

Status: the variant and this installed-VM test exist, and `just lint` runs
the collector's synthetic tests, but nothing has booted the variant yet.
Producing a report needs a separate, non-gating workflow that builds the
variant and runs this test on a hosted runner with KVM; it has not been added.
Ordinary-image and composefs CI do not exercise this variant. Draw no
conclusions about machine-id or installer configuration behavior until a
measured report is linked here.

## Build and test

```sh
just build          # podman build into containers-storage as atomic-linux:stable
just image-test     # run tests/image/*.sh in the built image with podman run
just lint           # shellcheck over the scripts
just hadolint       # Containerfile lint, in a container
just fmt-check      # Justfile formatting
```

With [bcvk](https://github.com/bootc-dev/bcvk) and rootless libvirt
(`qemu:///session`):

```sh
just ephemeral-smoke                       # stateless boot: identity, network, target
just vm-create && just vm-test             # persistent VM on a btrfs root
just k3s-vm-create && just k3s-vm-test     # enables k3s in the VM, runs k3s-validate
just kubevirt-test                         # nested KVM: disposable VM, KubeVirt L2 guest
```

`kubevirt-test` needs nested virtualization on the machine running it and
removes the VM it creates; `KEEP_FAILED_VM=1` keeps a failed one.

## Release

[.github/workflows/build.yml](.github/workflows/build.yml) builds every pull
request and boots the result in two VM jobs on a GitHub-hosted runner with
KVM and a pinned bcvk: `vm-smoke` runs `just ephemeral-smoke`, and `vm-k3s`
runs `just k3s-vm-create` and `just k3s-vm-test`. Both test the build job's
saved image, checked by image ID, not a rebuild. KubeVirt (`just
kubevirt-test`) needs nested KVM inside the test VM and is not run in CI.

A push to `main` pushes the image to `ghcr.io/cgwalters-forge/atomic-linux`
as `git-<sha>` only. Once both VM jobs pass, the `promote` job retags that
digest as the version label (`44.YYYYMMDD`) and `stable`, after checking
that its config is the image the VM jobs booted; nothing is rebuilt. A
failed VM test leaves `stable` where it was, and `promote` skips a build
that is no longer the head of `main`. The workflow's
`GITHUB_TOKEN` (`packages: write`) is the only credential, and the job
summaries print the digest. Dependabot proposes digest bumps for the `FROM`
lines and action pins.

Not yet done: signing. The plan is a cosign key pair, not keyless signing,
because containers/image (and so bootc) cannot match keyless signatures to a
workflow identity. See the TODO at the end of the workflow.

## License

Apache-2.0, see [LICENSE](LICENSE). Derived from the Universal Blue finpilot
template; see [NOTICE](NOTICE) for attribution.

Generated-by: https://github.com/cgwalters/#llms
