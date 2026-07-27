# Silverblue with Nix and Homebrew

The published image supports AMD64 and ARM64 systems.

After installing and booting Fedora Silverblue, switch to this image:

```bash
sudo bootc switch ghcr.io/haoxiangliew/silverblue:latest
sudo reboot
```

Confirm the image is active:

```bash
sudo bootc status
```

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
sudo bootc upgrade
sudo reboot
```

## Rollback

```bash
sudo bootc rollback
sudo reboot
```
