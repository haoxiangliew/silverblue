ARG FEDORA_VERSION
FROM quay.io/fedora/fedora-silverblue:${FEDORA_VERSION:-version-required} AS packages

RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    dnf --refresh -y install nix nix-daemon

RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    dnf --refresh -y install gcc gcc-c++ make

# DNF does not apply rpm-ostree's automatic /opt relocation during image builds.
RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    install -d -m 0755 /var/opt && \
    dnf -y copr enable scottames/ghostty && \
    dnf -y copr enable imput/helium && \
    dnf -y remove firefox firefox-langpacks ptyxis && \
    rm -rf /usr/lib64/firefox && \
    dnf --refresh -y install ghostty helium-bin xdg-terminal-exec && \
    dnf -y copr remove scottames/ghostty && \
    dnf -y copr remove imput/helium && \
    install -d -m 0755 /usr/lib/opt && \
    mv /var/opt/helium /usr/lib/opt/helium && \
    rmdir /var/opt

FROM packages

COPY system_files /

RUN glib-compile-schemas /usr/share/glib-2.0/schemas

RUN systemctl enable nix.mount nix-daemon.service

COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

RUN systemctl preset \
    brew-setup.service \
    brew-update.timer \
    brew-upgrade.timer

RUN bootc container lint
