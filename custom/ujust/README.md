# ujust host commands

> This text is LLM generated.

`build/10-build.sh` consolidates the `.just` drop-ins here into
`/usr/share/ublue-os/just/60-custom.just` and installs a small `ujust` wrapper
for it. Run `ujust` or `ujust --list` to see the assembled commands, independent
of the current working directory.

## Host maintenance

- `ujust status`: show bootc's booted, staged and rollback images. The command
  does not change deployments, but bootc needs `sudo` to read them on a booted host.
- `ujust upgrade`: fetch and stage an upgrade with `sudo bootc upgrade`.
- `ujust rollback`: select the previous deployment with `sudo bootc rollback`.
  This changes the next boot, not shared data in `/var`.
- `ujust reboot`: ask before rebooting, with **No** selected by default to
  prevent accidental interruption of host workloads.
- `ujust update-and-reboot`: stage an upgrade, then run the same reboot prompt.
  An upgrade failure stops the recipe before the prompt.
- `ujust clean-containers`: interactively prune unused local Podman containers,
  networks and images, leaving pods and volumes intact.
- `ujust clean-container-volumes`: separately opt in to deleting unused Podman
  volumes, including named volumes and their persistent data. A default-no
  confirmation prevents accidental data loss; Podman also asks before pruning.

Upgrade and rollback do not reboot automatically. None of these recipes changes
automatic-update timers or service enablement. Cleanup does not use `sudo`:
rootless users affect only their own local Podman storage, even with a remote
connection configured. Review each Podman prompt before accepting it; volume
deletion is not undoable.

Application examples in [`custom-apps.just`](custom-apps.just) are separate from
host maintenance. Install host RPMs at image build time, not through ujust.

## Validation

Run `just build`, then `just image-test`. The existing offline image-test harness
runs `tests/image/ujust.sh` against the assembled image, checking that
`ujust --list` parses, the host recipes and their tools exist, the real
`podman` and `gum` accept the recipes' flags, and removed placeholder commands
are absent. It does not upgrade, reboot or prune the host.
