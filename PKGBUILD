# Maintainer: Lukas <dingenses2@gmail.com>
pkgname=omarchy-theme-switcher
pkgver=1.0.0
pkgrel=1
pkgdesc="TUI and scheduler for Omarchy theme switching (day/night, rotation, random-login)"
arch=('any')
url="https://github.com/LukasTrust/omarchyThemeSwitcher"
license=('MIT')
depends=('bash' 'gum' 'omarchy')
optdepends=(
    'systemd: for automated timer-based switching'
    'sunwait: accurate geolocation-based sunrise/sunset times'
    'curl: IP-based location detection in TUI'
)
install="$pkgname.install"
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

# For local development/testing: override source with local files
# source=("$pkgname::git+file:///path/to/omarchyThemeSwitcher")

prepare() {
    # Nothing to prepare for a shell-only package
    true
}

package() {
    local src="${srcdir}/${pkgname}-${pkgver}"

    # Fallback for local builds where directory name may differ
    if [[ ! -d "$src" ]]; then
        src="${srcdir}/${pkgname}"
    fi
    if [[ ! -d "$src" ]]; then
        src="${srcdir}"
    fi

    # Executables
    install -Dm755 "$src/src/omarchy-theme-switcher" \
        "$pkgdir/usr/bin/omarchy-theme-switcher"
    install -Dm755 "$src/src/omarchy-theme-switcherd" \
        "$pkgdir/usr/bin/omarchy-theme-switcherd"

    # Library files
    install -Dm644 "$src/lib/config.sh" \
        "$pkgdir/usr/lib/omarchy-theme-switcher/config.sh"
    install -Dm644 "$src/lib/theme.sh" \
        "$pkgdir/usr/lib/omarchy-theme-switcher/theme.sh"
    install -Dm644 "$src/lib/geo.sh" \
        "$pkgdir/usr/lib/omarchy-theme-switcher/geo.sh"
    install -Dm644 "$src/lib/schedule.sh" \
        "$pkgdir/usr/lib/omarchy-theme-switcher/schedule.sh"
    install -Dm644 "$src/lib/tui.sh" \
        "$pkgdir/usr/lib/omarchy-theme-switcher/tui.sh"

    # systemd user units
    install -Dm644 "$src/systemd/omarchy-theme-switcher.service" \
        "$pkgdir/usr/lib/systemd/user/omarchy-theme-switcher.service"
    install -Dm644 "$src/systemd/omarchy-theme-switcher.timer" \
        "$pkgdir/usr/lib/systemd/user/omarchy-theme-switcher.timer"

    # Shell completions
    install -Dm644 "$src/completions/omarchy-theme-switcher.bash" \
        "$pkgdir/usr/share/bash-completion/completions/omarchy-theme-switcher"
    install -Dm644 "$src/completions/_omarchy-theme-switcher" \
        "$pkgdir/usr/share/zsh/site-functions/_omarchy-theme-switcher"
    install -Dm644 "$src/completions/omarchy-theme-switcher.fish" \
        "$pkgdir/usr/share/fish/vendor_completions.d/omarchy-theme-switcher.fish"

    # Icon
    install -Dm644 "$src/assets/icon.svg" \
        "$pkgdir/usr/share/pixmaps/omarchy-theme-switcher.svg"

    # License
    install -Dm644 "$src/LICENSE" \
        "$pkgdir/usr/share/licenses/$pkgname/LICENSE" 2>/dev/null || true
}
