ARG FEDORA_VERSION
FROM quay.io/fedora/fedora-silverblue:${FEDORA_VERSION:-version-required}

# Fedora's upstream Nix packages, with persistent storage configured below.
RUN dnf -y install nix nix-daemon && \
    dnf clean all && \
    rm -rf \
        /run/dnf \
        /var/cache/ldconfig/aux-cache \
        /var/cache/libdnf5 \
        /var/lib/dnf \
        /var/log/dnf5.log

COPY system_files /

RUN systemctl enable nix.mount nix-daemon.service

COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

RUN systemctl preset \
    brew-setup.service \
    brew-update.timer \
    brew-upgrade.timer

RUN bootc container lint
