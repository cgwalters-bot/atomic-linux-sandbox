# Installing on hardware

> This text is LLM generated.

Nothing here has been run on hardware yet (see the README's status). The
commands follow bootc's documentation as of November 2026:
[installation](https://bootc.dev/bootc/bootc-installation.7.html),
[`install to-existing-root`](https://bootc.dev/bootc/man/bootc-install-to-existing-root.8.html)
and [`switch`](https://bootc.dev/bootc/man/bootc-switch.8.html).

Use `IMAGE` below for the image you install: usually a derived image (see
"Deriving an image" in the [README](../README.md)), or
`ghcr.io/cgwalters-forge/atomic-linux:stable` to try the base. Images are
not signed yet. This guide covers the default ostree backend, not the
composefs variant.

## Onto an existing Fedora machine: `bootc install to-existing-root`

This installs the image into the machine's current root filesystem. bootc
wipes `/boot`, reinitializes the `EFI/` and `loader/` directories of the EFI
system partition and writes a new boot entry. Everything else on the root
filesystem stays where it was, but the new system does not use it: the old
root is visible under `/sysroot` after reboot. The old operating system no
longer boots, so there is no rollback to it.

### Before you start

- Back up what you cannot lose. Other systems booted from the same EFI
  system partition (for example Windows in `EFI/Microsoft`) may lose their
  boot entries when `EFI/` is reinitialized.
- Run as root on the machine itself, with podman installed. The running
  kernel writes the new system, so it must support the existing storage
  (LVM, LUKS, btrfs subvolumes). A root in a btrfs subvolume, as Fedora
  Workstation creates it, has not been tried with this image.
- Have a second machine that can reach this one over SSH. The image enables
  `sshd`, and the firewall's default zone allows SSH; until you recreate
  your user, root's SSH keys are the way in.
- Note your user's name, UID and GID (`id`), and where `/home` lives
  (`findmnt /home`): a separate partition or btrfs subvolume (the Fedora
  Workstation default) is not mounted by the new system.

### Install

Pull the image into root's container storage, then run the installer from
it:

```sh
podman pull IMAGE
podman run --rm --privileged --pid=host \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v /:/target \
  --security-opt label=type:unconfined_t \
  IMAGE \
  bootc install to-existing-root \
    --root-ssh-authorized-keys /target/root/.ssh/authorized_keys
```

`--root-ssh-authorized-keys` copies root's current `authorized_keys` (the
host is mounted at `/target`) into the new system; put your key there first,
or point the option at another file under `/target`. bootc waits a few
seconds before it starts so you can abort; `--acknowledge-destructive`
skips that. Don't pass `--cleanup` if you need anything from the old root:
it deletes files from the previous install on the first boot, before you
can copy them. Reboot when it finishes.

### What survives

| Path | In the new system |
| --- | --- |
| `/boot` | Wiped and rewritten |
| `/etc` | Fresh from the image; the old one is at `/sysroot/etc` |
| `/var` | Fresh and empty except what the image creates; the old one is at `/sysroot/var` |
| `/home` | A link to `/var/home`, which starts empty |
| Old `/home` on the root filesystem | Still at `/sysroot/home` |
| Old `/home` on another partition or subvolume | Untouched and unmounted |

Nothing is migrated for you: users, passwords, network connections,
container images, Flatpaks and libvirt VMs all need copying or reinstalling.

### After the first boot

Log in as root over SSH with the key you carried, check `bootc status`, then
bring back your user and data:

```sh
# Recreate the user with the old UID and GID so file ownership still matches.
groupadd -g 1000 alice && useradd -M -u 1000 -g 1000 -G wheel alice
passwd alice
# Old home on the root filesystem: /sysroot is read-only, so copy it.
cp -a --reflink=auto /sysroot/home/alice /var/home/alice
restorecon -R /var/home/alice
```

The password is for local and sudo use: sshd accepts keys only, so keep an
`~/.ssh/authorized_keys` in the copied home for SSH.

If the old `/home` is a separate partition or subvolume, mount it at
`/var/home` instead, with a kernel argument (bootc's preferred way over
editing `fstab`). Pass it at install time:

```sh
bootc install to-existing-root ... \
  --karg=systemd.mount-extra=UUID=<fs-uuid>:/var/home:btrfs:subvol=home
```

or add it afterwards with
`rpm-ostree kargs --append=systemd.mount-extra=...` and reboot.

Copy configuration you want from `/sysroot/etc` selectively, for example
NetworkManager profiles from
`/sysroot/etc/NetworkManager/system-connections/` (keep them mode 0600).
Don't copy generated files such as `resolv.conf`, and don't copy
`passwd`, `group` or `shadow` wholesale: the image keeps its system users in
`/usr/lib/passwd` and `/usr/lib/group`, and old entries would shadow them.
Anything every machine should have belongs in the derived image rather than
in `/etc`. When you have what you need, remove the old tree by hand after
`mount -o remount,rw /sysroot`, taking care to leave `/sysroot/ostree` and
`/sysroot/boot` alone.

## From Fedora Atomic: `bootc switch`

On Silverblue, Kinoite or another Fedora Atomic desktop, switching keeps
`/etc`, `/var` and `/home` and the current deployment as a rollback target:

```sh
sudo bootc switch IMAGE
sudo systemctl reboot
```

bootc refuses to switch a deployment with local rpm-ostree changes (layered
packages, overrides); remove them with `rpm-ostree reset` and reboot first,
or put them in the derived image. Alternatively
`rpm-ostree rebase ostree-unverified-registry:IMAGE` switches without
removing them. Changes you made in `/etc` stay and take precedence
over the image's defaults, so review `ostree admin config-diff` afterwards,
especially for firewalld zones and `containers/registries.conf`, which this
image ships.

## Fresh disks: `to-disk` and ISOs

`bootc install to-disk` erases a whole disk and installs the image with a
btrfs root (this image's default). Run it from another system with the
target disk attached, as root:

```sh
podman run --rm --privileged --pid=host --ipc=host \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers \
  -v ./authorized_keys:/authorized_keys:ro \
  --security-opt label=type:unconfined_t \
  IMAGE \
  bootc install to-disk --root-ssh-authorized-keys /authorized_keys /dev/sdX
```

An installer ISO needs osbuild's
[image-builder](https://osbuild.org/docs/developer-guide/projects/image-builder/usage/#bootc)
`bootc-installer` type, which also needs an installer container image; this
repository does not provide one, and bootc-image-builder's `anaconda-iso` is
[being deprecated](https://osbuild.org/docs/bootc/deprecation-notice/).

## Secure Boot

The image keeps Fedora's kernel and its signed shim and GRUB, so it boots
with Secure Boot enabled and nothing to enroll. MOK enrollment
(`mokutil --import`) is only needed if a derived image adds kernel modules
signed with a key outside Fedora's chain, such as the Universal Blue akmods
that `build/40-nvidia.sh.example` installs; enroll the public key of whoever
signed them before switching to such an image, or the modules will not load.

## Updates and rollback

The installed system fetches and stages updates in the background and never
reboots for them; the next boot uses the staged image. See
[updates.md](updates.md) for applying, rolling back, pinning and turning
the timer off.
