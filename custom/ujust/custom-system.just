# Show the booted, staged and rollback images (no changes).
[group('System')]
status:
    sudo bootc status

# Fetch and stage a host upgrade without rebooting or changing update timers.
[group('Maintenance')]
upgrade:
    sudo bootc upgrade

# Select the previous deployment for the next boot; does not reboot.
[group('Maintenance')]
rollback:
    sudo bootc rollback

# Reboot only after confirmation; default-no prevents accidental interruption.
[group('Maintenance')]
reboot:
    #!/usr/bin/bash
    set -euo pipefail
    # Do not let an inherited timeout submit the highlighted choice.
    if gum confirm --timeout=0s --default=false "Reboot the host now?"; then
        systemctl reboot
    fi

# Stage an upgrade, then ask before rebooting; a failed upgrade stops here.
[group('Maintenance')]
update-and-reboot:
    #!/usr/bin/bash
    set -euo pipefail
    sudo bootc upgrade
    ujust reboot

# Prune unused local containers, networks and images; keep pods and volumes.
[group('Maintenance')]
clean-containers:
    #!/usr/bin/bash
    set -euo pipefail
    unset CONTAINER_HOST CONTAINER_CONNECTION
    # System prune also removes stopped pods, which can delete anonymous volumes.
    podman --remote=false container prune
    podman --remote=false network prune
    podman --remote=false image prune --all

# Opt in to deleting unused volumes (including named volumes) and their data.
[group('Maintenance')]
clean-container-volumes:
    #!/usr/bin/bash
    set -euo pipefail
    unset CONTAINER_HOST CONTAINER_CONNECTION
    if gum confirm --timeout=0s --default=false "Permanently delete this user's unused Podman volumes and their data?"; then
        podman --remote=false volume prune
    fi
