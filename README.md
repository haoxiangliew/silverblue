# Silverblue with Nix and Homebrew

After installing and booting Fedora Silverblue, switch to this image:

```bash
sudo bootc switch ghcr.io/haoxiangliew/silverblue:latest
sudo reboot
```

Confirm the image is active:

```bash
sudo bootc status
```

## Homebrew

Homebrew is initialized automatically on the first boot. Start a new login shell after setup completes, then verify it:

```bash
systemctl status brew-setup.service --no-pager
brew --version
```

## Nix

Install Determinate Nix after booting this image:

```bash
curl --proto '=https' --tlsv1.2 -sSfL \
  https://install.determinate.systems/nix/tag/v3.21.8 | \
  sh -s -- install ostree --no-confirm --persistence=/var/lib/nix
```

The installer configures the persistent `/nix` mount and multi-user daemon. Verify the installation:

```bash
findmnt /nix
systemctl status nix.mount nix-daemon.socket --no-pager
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
