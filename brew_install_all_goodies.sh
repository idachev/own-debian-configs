#!/bin/bash
[ "$1" = -x ] && shift && set -x
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# macOS counterpart of apt_install_all_goodies_*.sh
# CLI stack first, then the GUI cask list. Safe to re-run.
# Each cask has a comment with what it is used for.

if [ "$(uname -s)" != Darwin ]; then
    echo "This script is for macOS. On Linux use apt_install_all_goodies.sh"
    exit 1
fi

"${DIR}/brew_install_no_gui.sh" "$@" || exit $?

# no_gui runs in a child shell; pick up Homebrew if this shell does not have it yet
if ! command -v brew >/dev/null 2>&1; then
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

failed=()

# GUI apps installed on the Apple Silicon Mac. The comment says why each one
# is on the list, so a fresh machine gets the same set for the same reasons.
casks=(
    postman             # REST/GraphQL API client
    calibre             # e-book library and format converter
    thunderbird         # mail client (see thunderbird_custom.sh)
    telegram            # messenger
    slack               # work chat
    keepassxc           # password manager (see lastpass_to_keepassxc.py)
    jetbrains-toolbox   # installs/updates IntelliJ, PyCharm, ...

    linearmouse         # per-device scroll direction/speed; modifier-key
                        # deceleration for the trackpad, tuned for AnyDesk
    karabiner-elements  # key remapping, Hyper Key, fast input source switcher
    supacode            # agent orchestrator / terminal manager
    ente-auth           # 2FA (TOTP) manager, GUI part; CLI = ente-cli formula
    opera               # secondary browser
    dropbox             # cloud storage, macOS File Provider integration
                        # (see dropbox-fix-conflicts.py, dropbox_restart.sh)
    anydesk             # remote desktop; the reason the scroll was optimized
    rectangle           # window snapping / tiling with the keyboard
    alt-tab             # Windows style Alt+Tab window switcher
)

for i in "${casks[@]}"; do
    echo -e "\n==> brew install --cask ${i}\n"
    brew install --cask "$i" || failed+=("$i")
done

echo -e "\n################################################################################"
echo "# GUI casks"
echo "################################################################################"
printf '  %s\n' "${casks[@]}"

echo
echo "First run needs macOS permissions in System Settings > Privacy & Security:"
echo "  Accessibility     -> Rectangle, AltTab, LinearMouse, AnyDesk"
echo "  Input Monitoring  -> Karabiner-Elements, LinearMouse"
echo "  Screen Recording  -> AltTab (window previews), AnyDesk"
echo "  Full Disk Access  -> AnyDesk (file transfer)"
echo "Dropbox asks to enable its File Provider extension on first launch."

if [ "${#failed[@]}" -gt 0 ]; then
    echo
    echo "Failed casks:"
    printf '  %s\n' "${failed[@]}"
    exit 1
fi
