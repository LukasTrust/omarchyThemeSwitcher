#!/usr/bin/env bash
# Install from the local git tree — use this during development instead of
# makepkg -si directly (which downloads from GitHub and may be stale).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
version=$(grep '^pkgver=' PKGBUILD | cut -d= -f2)
git archive --prefix="omarchy-theme-switcher-${version}/" HEAD \
    | gzip > "omarchy-theme-switcher-${version}.tar.gz"
makepkg -si "$@"
