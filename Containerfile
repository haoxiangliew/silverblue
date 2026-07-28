ARG FEDORA_VERSION
ARG NVIDIA_AKMODS_PLATFORM=linux/amd64
ARG FEDORA_IMAGE_DIGEST
ARG BREW_IMAGE_DIGEST
ARG NVIDIA_AKMODS_DIGEST

ARG DNF_PACKAGES_NIX="nix nix-daemon"
ARG DNF_PACKAGES_BUILD="gcc gcc-c++ make"
ARG DNF_PACKAGES_DESKTOP="ghostty helium-bin xdg-terminal-exec"
ARG DNF_PACKAGES_REMOVE="firefox firefox-langpacks ptyxis"
ARG DNF_PACKAGES_MULTIMEDIA="fdk-aac ffmpeg ffmpeg-libs ffmpegthumbnailer heif-pixbuf-loader libavcodec libfdk-aac libheif"
ARG DNF_PACKAGES_MULTIMEDIA_OVERRIDES="libheif libva mesa-dri-drivers mesa-filesystem mesa-libEGL mesa-libGL mesa-libgbm mesa-va-drivers mesa-vulkan-drivers"
ARG DNF_PACKAGES_MULTIMEDIA_OVERRIDES_AMD64="intel-gmmlib intel-mediasdk intel-vpl-gpu-rt libva-intel-media-driver"
ARG DNF_PACKAGES_AMD64="intel-vaapi-driver"
ARG DNF_PACKAGES_NVIDIA_KERNEL="kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra"

FROM --platform=${NVIDIA_AKMODS_PLATFORM} ghcr.io/ublue-os/akmods-nvidia-lts:main-${FEDORA_VERSION:-version-required}${NVIDIA_AKMODS_DIGEST:+@${NVIDIA_AKMODS_DIGEST}} AS nvidia-akmods
FROM ghcr.io/ublue-os/brew:latest${BREW_IMAGE_DIGEST:+@${BREW_IMAGE_DIGEST}} AS brew

FROM quay.io/fedora/fedora-silverblue:${FEDORA_VERSION:-version-required}${FEDORA_IMAGE_DIGEST:+@${FEDORA_IMAGE_DIGEST}} AS packages

ARG PACKAGE_FINGERPRINT
ARG DNF_PACKAGES_NIX
ARG DNF_PACKAGES_BUILD
ARG DNF_PACKAGES_DESKTOP
ARG DNF_PACKAGES_REMOVE
ARG DNF_PACKAGES_MULTIMEDIA
ARG DNF_PACKAGES_MULTIMEDIA_OVERRIDES
ARG DNF_PACKAGES_MULTIMEDIA_OVERRIDES_AMD64
ARG DNF_PACKAGES_AMD64

RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    test -n "${PACKAGE_FINGERPRINT}" && \
    dnf --refresh -y install ${DNF_PACKAGES_NIX}

RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    dnf --refresh -y install ${DNF_PACKAGES_BUILD}

# Adapted from ublue-os/main's Apache-2.0 multimedia setup.
RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    dnf config-manager setopt fedora-multimedia.enabled=1 || \
      dnf config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo" && \
    dnf config-manager setopt fedora-multimedia.priority=90 && \
    set -- ${DNF_PACKAGES_MULTIMEDIA_OVERRIDES} && \
    if [ "$(rpm -E '%{_arch}')" = x86_64 ]; then \
      set -- "$@" ${DNF_PACKAGES_MULTIMEDIA_OVERRIDES_AMD64}; \
    fi && \
    dnf --refresh -y distro-sync --skip-unavailable --repo=fedora-multimedia "$@" && \
    dnf -y install ${DNF_PACKAGES_MULTIMEDIA} && \
    if [ "$(rpm -E '%{_arch}')" = x86_64 ]; then \
      dnf -y install ${DNF_PACKAGES_AMD64}; \
    fi

# DNF does not apply rpm-ostree's automatic /opt relocation during image builds.
RUN --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    install -d -m 0755 /var/opt && \
    dnf -y copr enable scottames/ghostty && \
    dnf -y copr enable imput/helium && \
    dnf -y remove ${DNF_PACKAGES_REMOVE} && \
    rm -rf /usr/lib64/firefox && \
    dnf --refresh -y install ${DNF_PACKAGES_DESKTOP} && \
    dnf -y copr remove scottames/ghostty && \
    dnf -y copr remove imput/helium && \
    install -d -m 0755 /usr/lib/opt && \
    mv /var/opt/helium /usr/lib/opt/helium && \
    rmdir /var/opt

FROM packages AS configured

COPY system_files /
COPY cosign.pub /etc/pki/containers/cosign.pub

RUN glib-compile-schemas /usr/share/glib-2.0/schemas

RUN systemctl enable nix.mount nix-daemon.service

COPY --from=brew /system_files /

RUN systemctl preset \
    brew-setup.service \
    brew-update.timer \
    brew-upgrade.timer

FROM configured AS nvidia

ARG DNF_PACKAGES_NVIDIA_KERNEL

# Adapted from ublue-os/main; the artifact's installer remains upstream-owned.
RUN --mount=type=bind,from=nvidia-akmods,source=/kernel-rpms,target=/tmp/kernel-rpms \
    --mount=type=bind,from=nvidia-akmods,source=/rpms,target=/tmp/akmods-rpms \
    --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/lib/dnf \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/run/dnf \
    . /tmp/akmods-rpms/kmods/nvidia-vars && \
    cd /usr/lib/kernel/install.d && \
    mv 05-rpmostree.install 05-rpmostree.install.bak && \
    mv 50-dracut.install 50-dracut.install.bak && \
    printf '#!/bin/sh\nexit 0\n' > 05-rpmostree.install && \
    printf '#!/bin/sh\nexit 0\n' > 50-dracut.install && \
    chmod +x 05-rpmostree.install 50-dracut.install && \
    set -- && \
    for package in ${DNF_PACKAGES_NVIDIA_KERNEL}; do \
      rpm --erase "${package}" --nodeps; \
      set -- "$@" "/tmp/kernel-rpms/${package}-${KERNEL_VERSION}.rpm"; \
    done && \
    rpm --erase kernel-tools kernel-tools-libs --nodeps && \
    rm -rf /usr/lib/modules && \
    dnf -y install "$@" && \
    mv 05-rpmostree.install.bak 05-rpmostree.install && \
    mv 50-dracut.install.bak 50-dracut.install && \
    install -d -m 0700 /var/roothome && \
    IMAGE_NAME=silverblue AKMODNV_PATH=/tmp/akmods-rpms \
      /tmp/akmods-rpms/ublue-os/nvidia-install.sh && \
    dnf -y copr remove ublue-os/staging && \
    DRACUT_NO_XATTR=1 dracut --no-hostonly --kver "${KERNEL_VERSION}" \
      --reproducible --verbose --add ostree --force \
      "/lib/modules/${KERNEL_VERSION}/initramfs.img" && \
    chmod 0600 "/lib/modules/${KERNEL_VERSION}/initramfs.img" && \
    rm -rf /boot /var/lib/rpm-state && \
    install -d -m 0755 /boot

RUN bootc container lint --fatal-warnings

FROM configured AS silverblue

RUN bootc container lint --fatal-warnings
