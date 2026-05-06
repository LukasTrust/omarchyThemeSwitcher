# AUR Publishing Checklist

## Prerequisites

- [ ] Create an account at https://aur.archlinux.org
- [ ] Add your SSH public key at `https://aur.archlinux.org/account/<username>/edit`

## First-time setup

- [ ] Test that AUR SSH access works:
  ```bash
  ssh -T aur@aur.archlinux.org
  ```
- [ ] Clone the (empty) AUR package repository:
  ```bash
  git clone ssh://aur@aur.archlinux.org/omarchy-theme-switcher.git ~/aur-omarchy-theme-switcher
  ```

## Each release

- [ ] Update `pkgver` in [PKGBUILD](PKGBUILD) to match the new version
- [ ] Update `sha256sums` in [PKGBUILD](PKGBUILD) with the real hash (get it from the GitHub release page after the workflow runs, or compute it manually):
  ```bash
  curl -sL https://github.com/LukasTrust/omarchyThemeSwitcher/archive/refs/tags/v<VERSION>.tar.gz | sha256sum
  ```
- [ ] Copy files into the AUR repo:
  ```bash
  cp PKGBUILD omarchy-theme-switcher.install ~/aur-omarchy-theme-switcher/
  ```
- [ ] Generate `.SRCINFO` (required by AUR):
  ```bash
  cd ~/aur-omarchy-theme-switcher
  makepkg --printsrcinfo > .SRCINFO
  ```
- [ ] Commit and push:
  ```bash
  git add PKGBUILD omarchy-theme-switcher.install .SRCINFO
  git commit -m "v<VERSION>"
  git push
  ```
- [ ] Verify the package appears at `https://aur.archlinux.org/packages/omarchy-theme-switcher`

## Triggering the GitHub release (workflow)

- [ ] Tag and push to trigger the release workflow:
  ```bash
  git tag v<VERSION>
  git push origin v<VERSION>
  ```
- [ ] Confirm the release and tarball appear on the GitHub releases page
- [ ] Copy the SHA256 from the release notes into the AUR PKGBUILD
