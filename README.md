# Silverblue with Nix and Homebrew

The standard image supports AMD64 and ARM64 systems. The NVIDIA image supports
AMD64 systems with NVIDIA's proprietary LTS driver.

## Installation

Choose an image:

```bash
IMAGE=silverblue
# Use IMAGE=silverblue-nvidia for the proprietary NVIDIA LTS driver.
```

After installing and booting Fedora Silverblue, rebase once without signature
verification to install the image's public key and signature policy:

```bash
sudo rpm-ostree rebase -r \
  "ostree-unverified-registry:ghcr.io/haoxiangliew/${IMAGE}:latest"
```

After booting the image, rebase again to verify it and record the signed origin:

```bash
sudo rpm-ostree rebase -r \
  "ostree-image-signed:docker://ghcr.io/haoxiangliew/${IMAGE}:latest"
```

Confirm the image is active:

```bash
rpm-ostree status
```

The unsigned transport is used only to bootstrap trust. All subsequent
`rpm-ostree upgrade` operations require a valid signature.

## Multimedia

Following Universal Blue's package setup, the image uses Negativo17's multimedia
repository for complete FFmpeg, HEIF/HEVC, and Vulkan Video support. The AMD64
image also includes Intel VA-API acceleration.

The NVIDIA image mounts Universal Blue's `akmods-nvidia-lts` artifact during the
build. That artifact supplies its matching kernel, proprietary LTS modules,
upstream installer, NVIDIA userspace and CUDA libraries, and the VA-API NVDEC
bridge.

## Desktop defaults

[Ghostty](https://copr.fedorainfracloud.org/coprs/scottames/ghostty/) replaces Ptyxis as the default terminal, and [Helium](https://copr.fedorainfracloud.org/coprs/imput/helium/) replaces Firefox as the default browser.

## Homebrew

Homebrew is initialized automatically on the first boot. Start a new login shell after setup completes, then verify it:

```bash
systemctl status brew-setup.service --no-pager
brew --version
```

## Nix

The image includes Fedora's officially supported upstream `nix` and `nix-daemon` packages. The multi-user daemon and persistent `/nix` bind mount are configured automatically. Verify them after reboot:

```bash
findmnt /nix
systemctl status nix.mount nix-daemon.service --no-pager
nix run nixpkgs#hello
```

## Updates

```bash
sudo rpm-ostree upgrade
sudo reboot
```

## Rollback

```bash
sudo rpm-ostree rollback
sudo reboot
```
