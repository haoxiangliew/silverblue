ARG FEDORA_VERSION
FROM quay.io/fedora/fedora-silverblue:${FEDORA_VERSION}

# Determinate Nix mounts its persistent store here after deployment.
RUN install -d -m 0755 -o root -g root /nix

COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

RUN systemctl preset \
    brew-setup.service \
    brew-update.timer \
    brew-upgrade.timer

RUN bootc container lint
